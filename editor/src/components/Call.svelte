<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";
  import Expression from "./Expression.svelte";

  export let metadata;
  export let function_;
  export let with_;
</script>

<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
>
  <Expression expression={function_} />(<Expression expression={with_} />)
</span>
