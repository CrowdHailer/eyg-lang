import { Ok, Error } from "./gleam.mjs";

export function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function onClick(f) {
  document.onclick = function (event) {
    let arg = event.target.closest("[data-click]")?.dataset?.click;
    // can deserialize in language
    if (arg) {
      f(arg);
    }
  };
}

export function onKeyDown(f) {
  document.onkeydown = function (event) {
    // let arg = event.target.closest("[data-keydown]")?.dataset?.click;
    // can deserialize in language
    // event.key
    // if (arg) {
    f(event.key);
    // }
  };
}

export function insertAfter(e, text) {
  e.insertAdjacentHTML("afterend", text);
}

export function map_new() {
  return new Map()
}

export function map_set(map, key, value) {
  return map.set(key, value)
}

export function map_get(map, key) {
  if (map.has(key)) {
    return new Ok(map.get(key))
  }
  return new Error(undefined)
}
export function map_size(map) {
  return map.size
}
