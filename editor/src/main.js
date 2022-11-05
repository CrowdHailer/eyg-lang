// import { main } from "../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/main";
import { compiled_string_append } from "../../eyg/build/dev/javascript/eyg/dist/eyg/interpreter/builtin.mjs";
import { deploy } from "../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/ui.mjs";
import * as Spreasheet from "../../eyg/build/dev/javascript/eyg/dist/spreadsheet/main.mjs";
import window from "window";

import App from "./Workspace.svelte";

const path = window.location.pathname.slice(1);
var deployPage = path == "deploy";
var app;

let target = new URL(document.currentScript.src).hash.slice(1);
if (deployPage) {
  deploy(window.location.search.slice(1)).then(({ init, update, render }) => {
    document.body.innerHTML =
      '<div class="w-full min-h-screen h-full bg-gray-100 flex"></div>';
    let container = document.querySelector("div");
    console.log(container);
    let state = init([]);
    container.innerHTML = render(state);

    window.addEventListener("click", function () {
      state = update(state);
      container.innerHTML = render(state);
    });
  });
} else if (path.startsWith("spreadsheet")) {
  // This tries to load REACT
  // Spreasheet.main();
} else if (target == "client") {
  window.Builtin = { append: compiled_string_append };
  ready(function () {
    window.Program({
      on_click: (f) => {
        // console.log(f);
        document.onclick = (event) => {
          console.log(event);
          f(event.target);
        };
        return [];
      },
      on_keydown: (f) => {
        // https://medium.com/analytics-vidhya/implementing-keyboard-controls-or-shortcuts-in-javascript-82e11fccbf0c
        document.onkeydown = (event) => f(event.key);
        return [];
      },
      display: (value) => {
        document.body.innerHTML = value;
        return [];
      },
    });
  });
} else {
  app = new App({
    target: document.body,
  });
}
// // export default app;

function ready(fn) {
  if (document.readyState !== "loading") {
    fn();
  } else {
    document.addEventListener("DOMContentLoaded", fn);
  }
}
