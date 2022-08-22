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
