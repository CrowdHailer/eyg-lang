<script>
  import { tick } from "svelte";
  import ErrorNotice from "./ErrorNotice.svelte";
  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  import { List } from "../gen/gleam";
  const Ast = Object.assign({}, AstBare, Builders);

  export let metadata;
  export let label;
  export let update_tree;

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
      update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    } else if (content !== label) {
      let node = Ast.variable(content);
      update_tree(metadata.path, node);
    }
  }
  function handleKeydown(event) {
    if (event.key === "(") {
      event.preventDefault();
      let node = Ast.call(Ast.variable(content), List.fromArray([]));
      update_tree(metadata.path, node);
      thenFocus(Ast.append_path(metadata.path, 1));
    } else if (
      (event.key === "Delete" || event.key === "Backspace") &&
      content === ""
    ) {
      update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    }
  }

  let content = label;
</script>

<span
  class="outline-none text-blue-500"
  id={metadata.path ? "p" + metadata.path.toArray().join(",") : ""}
  contenteditable=""
  style="min-width: 1em; display:inline-block"
  bind:innerHTML={content}
  on:keydown={handleKeydown}
  on:blur={handleBlur}
/>
<ErrorNotice type_={metadata.type_} />
