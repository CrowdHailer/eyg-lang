<script>
  import * as Typer from "../gen/eyg/typer";
  export let position;
  export let metadata;
  export let value;

  let error = false
  $: error = Typer.is_error(metadata)

  // Have global again. editor is global all the state belongs in it
  // mapping to the presentation will check that the cursors not gone awry
</script>

<span
  class="text-green-400 border-2 border-white focus:border-indigo-300 outline-none rounded inline-block"
  class:border-red-500={error}
  tabindex="-1"
  data-editor={"p:" + position.join(",")}
  >{value}</span
>

<!--  -->
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
