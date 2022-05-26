<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";

  export let metadata;
  export let value;
</script>

<span
  class="text-green-400 border-2 border-transparent outline-none rounded inline-block"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-ui={Display.marker(metadata)}>{value}</span
>

<style>
  span {
    white-space: pre;
  }
  span::before {
    content: '"';
  }
  span::after {
    content: '"';
  }
</style>
