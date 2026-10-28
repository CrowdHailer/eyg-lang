const bodies = new WeakMap();
export const identity = value => value;
export const apply = (fn, args) => Reflect.apply(fn, undefined, args);
export const isFunction = value => typeof value === "function";
export function wrap(body, invoke) {
  const fn = arg => invoke(fn, arg);
  bodies.set(fn, body);
  return fn;
}
export const body = fn => bodies.get(fn) ?? fn;
export const hasBody = fn => bodies.has(fn);
export const length = value => value.length;
export const index = (value, index) => value[index];
export const object = Object.fromEntries;
export function raise(value) { throw value; }
