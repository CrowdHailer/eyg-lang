import { Result$Ok, Result$Error } from "../../gleam.mjs";
export const keyboardEvent = event => event instanceof KeyboardEvent ? Result$Ok(event) : Result$Error(undefined);
