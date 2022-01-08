<script>
  import * as Display from "../gen/eyg/editor/display";

  export let metadata;
  export let name;
</script>

<span
  class="text-blue-800 border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}>{name}</span
>
