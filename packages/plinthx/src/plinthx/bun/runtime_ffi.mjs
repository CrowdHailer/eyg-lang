import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function get() {
  const bun = globalThis.Bun;
  return bun !== null && typeof bun === "object" ? Result$Ok(bun) : Result$Error(undefined);
}
export const collect = (bun, force) => { bun.gc(force); };
