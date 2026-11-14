// Match the shared browser adapter's bound-method and literal semantics.
globalThis.LuiMiricl = (() => {
  const methods = new WeakMap();
  function property(object, key) {
    const value = object[key];
    if (typeof value !== 'function') return value;
    if ((typeof object !== 'object' && typeof object !== 'function') || !object)
      return value.bind(object);
    let cache = methods.get(object);
    if (!cache) { cache = new Map(); methods.set(object, cache); }
    let entry = cache.get(key);
    if (!entry || entry.original !== value) {
      entry = {original: value, bound: value.bind(object)};
      cache.set(key, entry);
    }
    return entry.bound;
  }
  return {property, global(path) {
    if (path === 'null') return null;
    if (path === 'undefined') return undefined;
    if (path === 'true') return true;
    if (path === 'false') return false;
    return path.split(':').reduce(property, globalThis);
  }};
})();
