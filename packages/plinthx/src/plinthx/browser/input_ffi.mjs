import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function eventFile(event) {
  const file = event?.target?.files?.item(0);
  return file ? Result$Ok(file) : Result$Error(undefined);
}
