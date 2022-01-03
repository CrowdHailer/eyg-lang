<script>
  import * as Display from "../gen/eyg/editor/display";

  export let metadata;
</script>

<span
  class="text-pink-500 border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
  >todo <span>{metadata.type_}</span></span
>
{Display.marker(metadata)}
