<script>
  import Expression from "./Expression.svelte";
  import * as Typer from "../gen/eyg/typer";

  export let position;
  export let metadata;
  export let function_;
  export let with_;

  let error = false
  $: error = Typer.is_error(metadata)
</script>

<span
  class="border-2 border-white focus:border-indigo-300 outline-none rounded"
  class:border-red-500={error}
  tabindex="-1" data-editor={"p:" + position.join(",")}>
  <Expression
    expression={function_}
    position={position.concat(0)}
  />(<Expression expression={with_} position={position.concat(1)} />)
</span>
