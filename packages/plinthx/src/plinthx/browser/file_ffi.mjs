import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function fromDynamic(raw) {
  return typeof globalThis.File === "function" && raw instanceof globalThis.File
    ? Result$Ok(raw)
    : Result$Error();
}
