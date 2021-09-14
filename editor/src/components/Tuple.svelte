<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import { tick } from "svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import * as Edit from "../gen/eyg/ast/edit";
  import * as Option from "../gen/gleam/option";
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
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
  function handleKeydown(event) {
    const { key, ctrlKey } = event;
    let action;
    action = Edit.shotcut_for_tuple(key, ctrlKey);

    Option.map(action, (action) => {
      let edit = Edit.edit(action, metadata.path);
      event.preventDefault();
      event.stopPropagation();
      dispatch("edit", edit);
    });
  }
</script>

<span
  tabindex="-1"
  id={Ast.path_to_id(metadata.path)}
  on:keydown={handleKeydown}
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  >[{#each elements.toArray() as element, i}{#if i !== 0},&nbsp;{/if}<Expression
      expression={element}
      on:edit
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
