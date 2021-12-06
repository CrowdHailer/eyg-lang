<script>
  import * as Display from "../gen/eyg/editor/display";

  export let metadata;
</script>

<span
class="border-2 border-transparent outline-none rounded inline-block"
class:border-red-500={metadata.errored && !Display.is_target(metadata)}
class:border-indigo-300={Display.is_target(metadata)}
data-editor={Display.marker(metadata)}
></span>


<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
  span {
    white-space: pre;
  }
  span::before {
    content: ' ';
  }
  span::after {
    content: ' ';
  }
</style>
