<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/eyg/editor/display";

  export let metadata;
</script>

<span
  class="text-pink-500 border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-ui={Display.marker(metadata)}><span>{metadata.type_}</span></span
>
