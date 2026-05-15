import fs from "node:fs";
import { Result$Ok, Result$Error } from "../../../gleam.mjs";

export function readStdin() {
  try {
    return Result$Ok(fs.readFileSync(0, "utf8"));
  } catch (error) {
    return Result$Error(`failed to read stdin: ${error.message}`);
  }
}
