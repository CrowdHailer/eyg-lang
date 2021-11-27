<script>
  import Expression from "./Expression.svelte";
  import * as Typer from "../gen/eyg/typer";

  export let position;
  export let metadata;
  export let elements;
  export let global;
  let error = false
  $: error = Typer.is_error(metadata)
</script>

<span
  tabindex="-1"
  data-editor={"p:" + position.join(",")}
  class="border-2 border-white focus:border-indigo-300 outline-none rounded"
  class:border-red-500={error}
  >[{#each elements.toArray() as element, i}{#if i !== 0},&nbsp;{/if}<Expression
      position={position.concat(i)}
      expression={element}
      on:edit
      {global}
    />{/each}]</span
>
