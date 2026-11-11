// Loaded before the ECL module. All Lisp strings cross as Unicode codepoints;
// no application text is evaluated as Lisp or JavaScript.
var LuiECL = (() => {
  const values = new Map(), identities = new WeakMap(), roots = new Map();
  const rootIds = new WeakMap(), methods = new WeakMap();
  let next = 0;
  const timers = new Map();
  function forget(callback) {
    const id = rootIds.get(callback);
    if (id !== undefined) { _lui_release(id); roots.delete(id); }
  }
  const scheduled = {};
  for (const [start, stop] of [['requestAnimationFrame', 'cancelAnimationFrame'],
                               ['setTimeout', 'clearTimeout']]) {
    scheduled[start] = (callback, ...args) => {
      const token = globalThis[start]((...values) => {
        timers.delete(start + token);
        try { callback(...values); } finally { forget(callback); }
      }, ...args);
      timers.set(start + token, callback);
      return token;
    };
    scheduled[stop] = token => {
      globalThis[stop](token);
      const callback = timers.get(start + token);
      if (callback) { timers.delete(start + token); forget(callback); }
    };
  }
  const frames = new Map();
  const freeFrames = [];
  let nextFrame = 0;
  function retain(value) {
    let id = identities.get(value);
    if (!id) { id = ++next; identities.set(value, id); }
    const entry = values.get(id) || {value, count: 0};
    entry.count++;
    values.set(id, entry);
    return id;
  }
  function property(object, key) {
    const value = object[key];
    if (typeof value !== 'function') return value;
    // Preserve method receivers and callback identity (removeEventListener).
    if (rootIds.has(value)) return value;
    if ((typeof object !== 'object' && typeof object !== 'function') || !object)
      return value.bind(object);
    let cache = methods.get(object);
    if (!cache) { cache = new Map(); methods.set(object, cache); }
    let entry = cache.get(key);
    if (!entry || entry.original !== value) {
      entry = {original: value, bound: key === 'remove' ? (...args) => {
        const result = value.apply(object, args);
        if (typeof object.onclick === 'function') forget(object.onclick);
        return result;
      } : value.bind(object)};
      cache.set(key, entry);
    }
    return entry.bound;
  }
  return {
    property, frames, retain, rootIds,
    frame: args => {
      const id = freeFrames.length ? freeFrames.pop() : ++nextFrame;
      frames.set(id, args);
      return id;
    },
    finish: id => { if (frames.delete(id)) freeFrames.push(id); },
    execute: (id, op) => {
      const args = frames.get(id);
      let result;
      try {
        switch (op) {
          case 0: result = LuiECL.global(args[0]); break;
          case 1: result = args.slice(1).reduce(property, args[0]); break;
          case 2: {
            const parent = args.slice(2, -1).reduce(property, args[0]);
            parent[args[args.length - 1]] = args[1];
            break;
          }
          case 3: result = args[0](...args.slice(1)); break;
          case 4: result = Reflect.construct(args[0], args.slice(1)); break;
          case 5: LuiECL.release(args); break;
          case 6: roots.delete(args[0]); break;
          default: throw new Error('Unknown bridge operation ' + op);
        }
        frames.set(id, [result]);
        return 0;
      } catch (error) {
        frames.set(id, [String(error)]);
        return 1;
      }
    },
    get: id => values.get(id).value,
    global: path => {
      if (scheduled[path]) return scheduled[path];
      if (path === 'null') return null;
      if (path === 'undefined') return undefined;
      if (path === 'true') return true;
      if (path === 'false') return false;
      return path.split(':').reduce(property, globalThis);
    },
    release: ids => ids.forEach(id => {
      const entry = values.get(id);
      if (entry && --entry.count === 0) values.delete(id);
    }),
    root: (id, callable) => {
      if (!roots.has(id)) {
        const value = callable ? (...args) => {
          const frame = LuiECL.frame(args);
          try {
            if (!_lui_callback(id, frame)) throw new Error('LUI callback failed; see Lisp error');
          } finally { LuiECL.finish(frame); }
        } : {};
        roots.set(id, value); rootIds.set(value, id);
      }
      return roots.get(id);
    },
    dropRoot: id => { roots.delete(id); return null; }
  };
})();
