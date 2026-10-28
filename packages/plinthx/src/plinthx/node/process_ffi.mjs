import nativeProcess from "node:process";
import { Result$Ok, Result$Error,BitArray$BitArray, toList } from "../../gleam.mjs";

export function get() {
  const process = globalThis.process;
  return process instanceof nativeProcess.constructor ? Result$Ok(process) : Result$Error(undefined);
}
export const stdout = process => process.stdout;
export const stdin = process => process.stdin;

export function isTTY(stream) {
  return stream.isTTY === true
}

export function isRaw(stream) {
  return stream.isRaw
}

export function setRawMode(stream, mode) {
  return stream.setRawMode(mode)
}

export function columns(stream) {
  return stream.columns
}

export function rows(stream) {
  return stream.rows
}

export function resume(stream) {
  return stream.resume()
}

export function pause(stream) {
  return stream.pause()
}

function listen(stream, event, callback) {
  stream.on(event, callback)
  return () => { stream.off(event, callback) }
}

export function onResize(stream, callback) {
  return listen(stream, "resize", callback)
}

export function onData(stream, callback) {
  return listen(stream, "data", function(chunk) { callback(BitArray$BitArray(chunk)) })
}

export function onText(stream, callback) {
  stream.setEncoding("utf8")
  return listen(stream, "data", callback)
}

export function onEnd(stream, callback) {
  return listen(stream, "end", callback)
}

export function onError(stream, callback) {
  return listen(stream, "error", error => callback(String(error)))
}

export const env = process => toList(Object.entries(process.env));
export const heapBytes = process => process.memoryUsage().heapUsed;
