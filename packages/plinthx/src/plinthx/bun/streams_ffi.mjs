import { Result$Ok, Result$Error } from "../../gleam.mjs";

export async function toText(bun, stream) {
  try { return Result$Ok(await bun.readableStreamToText(stream)); }
  catch (error) { return Result$Error(String(error)); }
}
