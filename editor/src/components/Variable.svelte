<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";

  export let metadata;
  export let label;
</script>

<span
  class="outline-none text-blue-500 border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-ui={Display.marker(metadata)}>{label}</span
>

<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
</style>
