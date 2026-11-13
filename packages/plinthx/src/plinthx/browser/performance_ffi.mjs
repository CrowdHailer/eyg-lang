import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function get() {
  const performance = globalThis.performance;
  return globalThis.Performance && performance instanceof globalThis.Performance
    ? Result$Ok(performance) : Result$Error(undefined);
}
export const timeOrigin = performance => performance.timeOrigin;
export const now = performance => performance.now();
