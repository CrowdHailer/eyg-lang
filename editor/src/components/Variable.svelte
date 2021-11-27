<script>
  import * as Typer from "../gen/eyg/typer";

  export let position;
  export let metadata;
  export let label;
  export let global;

  let error = false
  $: error = Typer.is_error(metadata)
</script>

<!-- Don't edit delte replace with autocomplete -->
<span
  class="outline-none text-blue-500 border-2 border-white focus:border-indigo-300 outline-none rounded"
  class:border-red-500={error}
  tabindex="-1"
  data-editor={"p:" + position.join(",")}>{label}</span
>

<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
</style>
