import Workspace from "../../../../../../editor/src/Workspace.svelte";
// import * as Gleam from "../build/dev/javascript/eyg/dist/gleam.mjs";

export function render() {
  let ws = new Workspace({
    target: document.body,
  });
  return function (params) {
    ws.$set(params);
  };
}

// Gleam extension

import * as G from "gleam.mjs";

// All of my things are function 1
export function dynamic_function(f) {
  if (typeof f == "function" && f.length == 1) {
    console.log("IS ALL OK");
    return new G.Ok(f);
  } else {
    console.log("IS BAD");
    return new G.Error(G.Empty());
  }
}
