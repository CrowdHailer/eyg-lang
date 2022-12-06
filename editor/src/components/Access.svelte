<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/eyg/editor/display";
  import Expression from "./Expression.svelte";

  export let metadata;
  export let value;
  export let key;

  let key_display;
  $: key_display = Display.display_access_key(metadata);
</script>

<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-ui={Display.marker(metadata)}
>
  <Expression expression={value} />.<span
    class="border-2 border-transparent outline-none rounded"
    class:border-red-500={key_display.errored &&
      !Display.is_target(key_display)}
    class:border-indigo-300={Display.is_target(key_display)}
    data-ui={Display.marker(key_display)}>{key}</span
  >
</span>
