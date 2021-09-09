<script>
  import { tick } from "svelte";
  import ErrorNotice from "./ErrorNotice.svelte";
  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  import { List } from "../gen/gleam";
  const Ast = Object.assign({}, AstBare, Builders);
  import { resolve, how_many_args } from "../gen/eyg/typer/monotype";

  export let metadata;
  export let label;
  export let global;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element.focus();
    });
  }

  // focus next can walk up a tree
  function handleBlur(event) {
    if (content.trim() === "") {
      event.preventDefault();
      global.update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    } else if (content !== label) {
      let node = Ast.variable(content);
      global.update_tree(metadata.path, node);
    }
  }
  let letters = ["a", "b", "c", "d", "e"].map(Ast.variable);
  function handleKeydown(event) {
    if (event.key === "(") {
      event.preventDefault();
      let argCount = how_many_args(
        resolve(metadata.type_["0"], global.typer.substitutions)
      );
      let node = Ast.call(
        Ast.variable(content),
        List.fromArray(letters.slice(0, argCount))
      );
      global.update_tree(metadata.path, node);
      thenFocus(Ast.append_path(metadata.path, 1));
    } else if (
      (event.key === "Delete" || event.key === "Backspace") &&
      content === ""
    ) {
      global.update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    }
  }

  let content = label;
</script>

<span
  class="outline-none text-blue-500"
  id={metadata.path ? "p" + metadata.path.toArray().join(",") : ""}
  contenteditable=""
  bind:innerHTML={content}
  on:keydown={handleKeydown}
  on:blur={handleBlur}
/><ErrorNotice type_={metadata.type_} />

<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
</style>
