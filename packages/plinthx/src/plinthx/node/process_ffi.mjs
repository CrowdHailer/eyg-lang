import nativeProcess from "node:process";
import { Result$Ok, Result$Error, toList } from "../../gleam.mjs";

export function get() {
  const process = globalThis.process;
  return process instanceof nativeProcess.constructor ? Result$Ok(process) : Result$Error(undefined);
}
export const stdout = process => process.stdout;
export const isTTY = stream => typeof stream.isTTY === "boolean" ? Result$Ok(stream.isTTY) : Result$Error(undefined);
export const env = process => toList(Object.entries(process.env));
