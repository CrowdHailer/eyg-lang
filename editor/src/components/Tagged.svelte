<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";
  import Expression from "./Expression.svelte";

  export let metadata;
  export let tag;
  export let value;
</script>

<span
  class="text-blue-800 font-bold border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
  ><span>{tag}</span>{#if !Display.is_unit(value)}<Expression
      expression={value}
    />{/if}</span
>
