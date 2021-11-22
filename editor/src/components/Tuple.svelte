<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import Hole from "./Hole.svelte";
  export let position;
  export let metadata;
  export let elements;
  export let global;
</script>

<span
  tabindex="-1"
  data-position={"p" + position.join(",")}
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  >[{#each elements.toArray() as element, i}{#if i !== 0},&nbsp;{/if}<Expression
      position={position.concat(i)}
      expression={element}
      on:edit
      {global}
    />{:else}<Hole
      {position}
      metadata={Object.assign({}, metadata, {
        path: Ast.append_path(metadata.path, elements.toArray().length),
      })}
      {global}
    />{/each}]</span
><ErrorNotice type_={metadata.type_} />
