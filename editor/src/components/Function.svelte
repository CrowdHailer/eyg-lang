<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";

  export let position;
  export let metadata;
  export let global;
  export let pattern;
  export let body;
</script>

(<Pattern {pattern} {metadata} {global} position={position.concat(0)} />)
<strong
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  tabindex="-1"
  data-editor={"p:" + position.join(",")}>=></strong
>
<Indent>
  <Expression
    expression={body}
    on:edit
    {global}
    position={position.concat(1)}
  />
</Indent>
