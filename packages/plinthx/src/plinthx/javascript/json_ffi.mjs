import { Result$Ok, Result$Error } from "../../gleam.mjs";
export function stringify(value) {
  try {
    const text = JSON.stringify(value);
    return text === undefined ? Result$Error("value is not JSON-encodable") : Result$Ok(text);
  } catch (error) { return Result$Error(String(error)); }
}
