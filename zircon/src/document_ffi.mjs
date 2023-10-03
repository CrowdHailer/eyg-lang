import { Ok, Error } from "./gleam.mjs";

export function querySelector(query) {
  let found = document.querySelector(query);
  if (!found) {
    return new Error();
  }
  return new Ok(found);
}

export function querySelectorAll(query) {
  return Array.from(document.querySelectorAll(query));
}
