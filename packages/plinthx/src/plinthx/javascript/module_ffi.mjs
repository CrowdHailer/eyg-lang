import { Result$Ok, Result$Error } from "../../gleam.mjs";
export const url = () => import.meta.url;
export async function load(specifier) {
  try { return Result$Ok(await import(specifier)); }
  catch (error) { return Result$Error(String(error)); }
}
