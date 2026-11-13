import { Result$Ok, Result$Error } from "../../gleam.mjs";
import { Some, None } from "../../../gleam_stdlib/gleam/option.mjs";

export function getTextReader(stream) {
  try { return Result$Ok(stream.pipeThrough(new TextDecoderStream()).getReader()); }
  catch (error) { return Result$Error(String(error)); }
}
export async function readText(reader) {
  try {
    const chunk = await reader.read();
    return Result$Ok(chunk.done ? new None() : new Some(chunk.value));
  } catch (error) { return Result$Error(String(error)); }
}
