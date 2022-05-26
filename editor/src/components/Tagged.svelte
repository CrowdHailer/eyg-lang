<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";
  import Expression from "./Expression.svelte";

  export let metadata;
  export let tag;
  export let value;

  let tag_display;
  $: tag_display = Display.display_tag(metadata);
</script>

<!-- needs an else that passes in an empty tuple -->
<!-- {#if !Display.is_unit(value)}<Expression expression={value} />{/if} -->
<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-ui={Display.marker(metadata)}
  ><span
    class="text-blue-800 font-bold border-2 border-transparent outline-none rounded"
    class:border-red-500={tag_display.errored &&
      !Display.is_target(tag_display)}
    class:border-indigo-300={Display.is_target(tag_display)}
    data-ui={Display.marker(tag_display)}>{tag}</span
  ><Expression expression={value} /></span
>
