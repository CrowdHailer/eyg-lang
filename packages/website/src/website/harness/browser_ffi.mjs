import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function href(location) {
  try {
    return Result$Ok(location.href);
  } catch (error) {
    return Result$Error(`${error}`);
  }
}