export const click = element => { element.click(); };
export const scrollNearest = element => { element.scrollIntoView({ block: "nearest" }); };
export const contentWindow = element => element.contentWindow ? Result$Ok(element.contentWindow) : Result$Error(undefined);
import { Result$Ok, Result$Error } from "../../gleam.mjs";
