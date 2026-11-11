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
  const string = s => '(:string ' + Array.from(s, c => c.codePointAt(0)).join(' ') + ')';
  function pack(value) {
    if (value === null) return '(:null)';
    if (value === undefined) return '(:undefined)';
    if (typeof value === 'boolean') return value ? '(:true)' : '(:false)';
    if (typeof value === 'string') return string(value);
    if (typeof value === 'number') {
      if (!Number.isFinite(value)) throw new Error('Non-finite browser number');
      return '(:number ' + String(value).replace('e', 'd') + ')';
    }
    if (rootIds.has(value)) return '(:root ' + rootIds.get(value) + ')';
    let id = identities.get(value);
    if (!id) { id = ++next; identities.set(value, id); }
    const entry = values.get(id) || {value, count: 0};
    entry.count++;
    values.set(id, entry);
    return '(:reference ' + id + ')';
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
    pack, property,
    perform: operation => {
      try { return pack(operation()); }
      catch (error) { return '(:error ' + string(String(error)).slice(1); }
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
          const text = '(' + args.map(pack).join(' ') + ')';
          const pointer = stringToNewUTF8(text);
          try {
            if (!_lui_callback(id, pointer)) throw new Error('LUI callback failed; see Lisp error');
          } finally { _free(pointer); }
        } : {};
        roots.set(id, value); rootIds.set(value, id);
      }
      return roots.get(id);
    },
    dropRoot: id => { roots.delete(id); return null; }
  };
})();
