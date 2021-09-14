<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import * as Edit from "../gen/eyg/ast/edit";
  import * as Option from "../gen/gleam/option";
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
  import Hole from "./Hole.svelte";
  export let position;
  export let metadata;
  export let elements;
  export let global;

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
      position={position.concat(i)}
      expression={element}
      on:edit
      {global}
    />{:else}<Hole
      metadata={Object.assign({}, metadata, {
        path: Ast.append_path(metadata.path, elements.toArray().length),
      })}
      {global}
    />{/each}]</span
>
<ErrorNotice type_={metadata.type_} />
