<script>
  import { tick } from "svelte";
  import * as Ast from "../gen/eyg/ast";
  import * as Pattern from "../gen/eyg/ast/pattern";
  import { List } from "../gen/gleam";

  export let metadata;
  export let pattern;
  export let global;
  console.log(global);

  function handleLabelChange(newLabel) {
    if (newLabel != pattern.label) {
      global.update_tree(
        metadata.path,
        Ast.let_(Pattern.variable(newLabel), value, then)
      );
    } else {
    }
  }
  function thenFocus(path, rest) {
    tick().then(() => {
      // let pathId = "p" + path.toArray().join(",") + (rest || "");
      let element = document.getElementById(pathId);
      element.focus();
    });
  }
  function handleDelete(child) {
    let childPath = Ast.append_path(metadata.path, child);
    global.update_tree(childPath, Ast.hole());
    thenFocus(childPath);
  }
  let newContent;
  $: newContent = pattern.label;
  let modified = false;
  function handleBlur() {
    if (!modified) {
      handleLabelChange(newContent);
    }
  }

  function handleKeydown(event) {
    if (event.key === "[") {
      pattern;
      global.update_tree(
        metadata.path,
        Ast.let_(Pattern.tuple_(List.fromArray([])), value, then)
      );
      event.preventDefault();
      modified = true;
      thenFocus(metadata.path, "e" + 0);
    } else if (event.key === "{") {
    } else {
    }
  }
  let elements = [];
  $: elements = pattern?.elements?.toArray()?.concat("");
  let updatedElements = elements;

  function handleBlurElement(event, i, newLabel) {
    // TODO trim in Gleam
    newLabel = newLabel.trim().replace(" ", "_");
    if (newLabel) {
      let newPattern = Pattern.replace_element(pattern, i, newLabel);
      let newNode = Ast.let_(newPattern, value, then);
      global.update_tree(metadata.path, newNode);
      thenFocus(metadata.path, "e" + (i + 1));
    } else {
    }
  }
</script>

<!-- Bubble everything to the top does an onchange event bubble -->

{#if Pattern.is_variable(pattern)}
  <!-- add a p0 on the end of the id tree -->
  <!-- bubble event out from here -->
  <!-- Think more about tope level everything BUT that means we need to capture key presses for editing variables and binary -->
  <span
    class="border-b border-white min-w-10 outline-none focus:border-gray-900 focus:border-2 required"
    contenteditable=""
    bind:textContent={newContent}
    on:keydown={handleKeydown}
    on:blur={handleBlur}>{pattern.label}</span
  >
{:else if Pattern.is_tuple(pattern)}
  [{#each elements as _element, i}
    <span
      class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
      id={Ast.path_to_id(metadata.path) + "e" + i}
      contenteditable=""
      bind:textContent={updatedElements[i]}
      on:blur={(e) => handleBlurElement(e, i, updatedElements[i])}
    />{#if i < elements.length - 1}
      ,
    {/if}
  {/each}
  ]
{:else}{JSON.stringify(pattern)}{/if}

<style>
  span.required {
    display: inline-block;
  }
  span:empty.required {
    min-width: 1em;
  }
</style>
