import { Result$Ok, Result$Error } from "../../gleam.mjs";
import { Some, None } from "../../../gleam_stdlib/gleam/option.mjs";

export function get() {
  const fetch = globalThis.fetch;
  return typeof fetch === "function" ? Result$Ok(fetch) : Result$Error(undefined);
}
export async function send(fetch, url, init) {
  try {
    return Result$Ok(await fetch(url, {
      method: init.method, headers: Array.from(init.headers), body: init.body,
      signal: init.signal instanceof Some ? init.signal[0] : undefined,
    }));
  } catch (error) { return Result$Error(String(error)); }
}
export const status = response => response.status;
export const requestUrl = request => request.url;
export const requestHeader = (request, name) => {
  const value = request.headers.get(name);
  return value === null ? new None() : new Some(value);
};
export function getResponse() {
  const constructor = globalThis.Response;
  return typeof constructor === "function" ? Result$Ok(constructor) : Result$Error(undefined);
}
export function newResponse(constructor, body, status, headers) {
  try { return Result$Ok(new constructor(body, { status, headers: Array.from(headers) })); }
  catch (error) { return Result$Error(String(error)); }
}
export function newResponseBits(constructor, body, status, headers) {
  try {
    if (body.bitSize % 8 !== 0) return Result$Error("response body must contain whole bytes");
    const bytes = body.bitOffset === 0 ? body.rawBuffer : Uint8Array.from({ length: body.byteSize }, (_, i) => body.byteAt(i));
    return Result$Ok(new constructor(bytes, { status, headers: Array.from(headers) }));
  } catch (error) { return Result$Error(String(error)); }
}
export async function text(response) {
  try { return Result$Ok(await response.text()); }
  catch (error) { return Result$Error(String(error)); }
}
