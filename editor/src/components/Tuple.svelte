<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import { tick } from "svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import Hole from "./Hole.svelte";
  export let metadata;
  export let elements;
  export let global;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element?.focus();
    });
  }
  function handleDeletebackwards(_event) {
    let len = elements.toArray().length;
    if (len) {
      thenFocus(Ast.append_path(len - 1));
    } else {
      global.update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    }
  }
  let container;
  let tabindex = "-1";
  function handleKeydown(event) {
    if (event.ctrlKey && event.key === "+") {
      if (tabindex === "0") {
        tabindex = "-1";
        console.log("bubble");
      } else {
        event.preventDefault();
        event.stopPropagation();
        tabindex = "0";
        container.focus();
      }
    } else {
    }
  }
  function handleBlur(event) {
    tabindex = "-1";
  }
</script>

<span
  {tabindex}
  on:keydown={handleKeydown}
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  bind:this={container}
  on:blur={handleBlur}
  >[{#each elements.toArray() as element, i}{#if i !== 0},&nbsp;{/if}<Expression
      expression={element}
      {global}
    />{/each}<Hole
    metadata={Object.assign({}, metadata, {
      path: Ast.append_path(metadata.path, elements.toArray().length),
    })}
    {global}
    on:deletebackwards={handleDeletebackwards}
  />]</span
>
<ErrorNotice type_={metadata.type_} />
