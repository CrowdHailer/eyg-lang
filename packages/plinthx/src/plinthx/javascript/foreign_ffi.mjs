import { Result$Ok, Result$Error } from "../../gleam.mjs";
const bodies = new WeakMap();
export const identity = value => value;
export const nullValue = () => null;
export const apply = (fn, args) => Reflect.apply(fn, undefined, args);
export const call = (object, method, args) => Reflect.apply(object[method], object, args);
export const isFunction = value => typeof value === "function";
export const isUndefined = value => value === undefined;
export const isUint8Array = value => value instanceof Uint8Array;
export const isThenable = value => value != null && typeof value.then === "function";
export const error = message => new Error(message);
export function tryApply(fn, args) {
  try { return Result$Ok(Reflect.apply(fn, undefined, args)); }
  catch (error) { return Result$Error(error); }
}
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
export const hasOwn = (object, key) => Object.hasOwn(object, key);
export const property = (object, key) => object[key];
export const promise = value => Promise.resolve(value);
export function raise(value) { throw value; }
