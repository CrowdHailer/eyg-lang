<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";

  export let metadata;
  export let name;
  // This is the inner expression
  export let expression;
</script>

<span
  class="text-blue-800 font-bold border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}>{name}</span
>{#if !Display.is_unit(expression)}<Expression {expression} />{/if}
