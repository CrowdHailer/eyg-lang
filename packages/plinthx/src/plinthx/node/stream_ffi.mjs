import { Result$Ok, Result$Error } from "../../gleam.mjs";

const attempt = callback => {
  try { callback(); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
};
export const setEncoding = (stream, encoding) => attempt(() => stream.setEncoding(encoding));
export const onData = (stream, callback) => attempt(() => stream.on("data", callback));
export const offData = (stream, callback) => attempt(() => stream.off("data", callback));
export const resume = stream => attempt(() => stream.resume());
export const pause = stream => attempt(() => stream.pause());
