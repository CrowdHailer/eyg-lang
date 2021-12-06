<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";

  export let metadata;
  export let elements;
</script>

<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
  >[{#each elements.toArray() as element, i}{#if i !== 0},&nbsp;{/if}<Expression
      expression={element}
    />{/each}]</span
>
