import * as Gleam from "./gleam.mjs";

export async function fetchSource() {
  let response = await fetch("/saved.json");
  return await response.text();
}

export async function fetchText(url) {
  let response = await fetch(url);
  return await response.text();
}

export async function post(url, data) {
  try {
    let response = await fetch(url, {
      method: "POST",
      body: data,
    });
    console.log(response.status);
    return new Gleam.Ok([]);
  } catch (error) {
    new Gleam.Error(error);
  }
}

export function tryCatch(f) {
  try {
    return new Gleam.Ok(f());
  } catch (error) {
    return new Gleam.Error(error);
  }
}

// for morph
export function listenKeypress(dispatch) {
  // https://medium.com/analytics-vidhya/implementing-keyboard-controls-or-shortcuts-in-javascript-82e11fccbf0c
  document.addEventListener("keydown", function (event) {
    if (document.activeElement === document.body) {
      if (event.altKey || event.ctrlKey || event.metaKey) {
        // These should behave normally
        return;
      } else {
        event.preventDefault();
      }
    }
    dispatch(event.key);
  });
}
