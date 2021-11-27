<script>
  import Expression from "./Expression.svelte";
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
    />{/each}]</span
>
