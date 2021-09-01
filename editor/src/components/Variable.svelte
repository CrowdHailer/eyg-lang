<script>
  import { tick, createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();

  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

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
      dispatch("delete", {});
    } else if (content !== label) {
      let node = Ast.variable(content);
      update_tree(metadata.path, node);
    }
  }
  function handleKeydown(event) {
    if (event.key === "(") {
      event.preventDefault();
      let node = Ast.call(Ast.variable(content), Ast.hole());
      update_tree(metadata.path, node);
      thenFocus(Ast.append_path(metadata.path, 1));
    } else {
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
/>
{#if metadata.type_.type == "Error"}
  <div class=" bg-red-100 border-t-2 border-red-300 py-1 px-4">
    Unknown variable {label}
  </div>
{/if}
