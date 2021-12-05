<script>
  import Expression from "./Expression.svelte";
  import Pattern from "./Pattern.svelte";
  import * as Editor from "../gen/eyg/ast/editor";
  import Indent from "./Indent.svelte";
  import * as Typer from "../gen/eyg/typer";

  export let position;
  export let metadata;
  export let pattern;
  export let value;
  export let then;

  let error = false
  $: error = Typer.is_error(metadata)

  let multiline = false;
  multiline = Editor.is_multiexpression(value)
</script>

<p
  tabindex="-1"
  class="border-2 border-white focus:border-indigo-300 outline-none rounded"
  class:border-red-500={error}
  data-editor={"p:" + position.join(",")}
>
  <span class="text-yellow-400">let</span>
  <Pattern
    {pattern}
    {metadata}
    position={position.concat(0)}
  />
  =
  {#if multiline}
  <Indent>
    <Expression
      expression={value}
      position={position.concat(1)}
    />
  </Indent>
  {:else}
  <Expression
    expression={value}
    position={position.concat(1)}
  />
  {/if}
</p>
<Expression
  expression={then}
  position={position.concat(2)}
/>
