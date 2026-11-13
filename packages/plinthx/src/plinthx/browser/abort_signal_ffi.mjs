import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function get() {
  const constructor = globalThis.AbortSignal;
  return typeof constructor === "function" ? Result$Ok(constructor) : Result$Error(undefined);
}
export function timeout(constructor, milliseconds) {
  try { return Result$Ok(constructor.timeout(milliseconds)); }
  catch (error) { return Result$Error(String(error)); }
}
