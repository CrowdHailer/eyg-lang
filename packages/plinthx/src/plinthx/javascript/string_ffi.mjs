import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function from(value) {
  try { return Result$Ok(String(value)); }
  catch (error) { return Result$Error(String(error)); }
}
