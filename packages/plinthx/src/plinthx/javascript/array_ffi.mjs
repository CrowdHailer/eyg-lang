import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function push(array, value) {
  try { return Result$Ok(array.push(value)); }
  catch (error) { return Result$Error(String(error)); }
}
export function splice(array, start, deleteCount, items) {
  try { return Result$Ok(array.splice(start, deleteCount, ...items)); }
  catch (error) { return Result$Error(String(error)); }
}
