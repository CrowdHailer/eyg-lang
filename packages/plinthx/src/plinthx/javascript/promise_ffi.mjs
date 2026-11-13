import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function get() {
  const constructor = globalThis.Promise;
  return typeof constructor === "function" ? Result$Ok(constructor) : Result$Error(undefined);
}
export const reject = (constructor, reason) => constructor.reject(reason);
