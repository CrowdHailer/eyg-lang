import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function eval_(string) {
  try {
    return Result$Ok(eval(string));
  } catch (error) {
    return Result$Error(error.toString());
  }
}

export function list(items) {
  return items.reduceRight((acc, element) => {
    return [element, acc]
  }, []);
}

export function object(entries) {
  return Object.fromEntries(entries)
}