<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";
  import * as Editor from "../gen/eyg/ast/editor";
  import * as Typer from "../gen/eyg/typer";

  export let position;
  export let metadata;
  export let pattern;
  export let body;

  let multiline = false;
  multiline = Editor.is_multiexpression(body)


  let error = false
  $: error = Typer.is_error(metadata)
</script>

<Pattern {pattern} {metadata} position={position.concat(0)} />
<strong
  class="border-2 border-white focus:border-indigo-300 outline-none rounded"
  class:border-red-500={error}
  tabindex="-1"
  data-editor={"p:" + position.join(",")}>=></strong
>
{#if multiline}
<Indent>
  <Expression
    expression={body}
    position={position.concat(1)}
  />
</Indent>
  {:else}
  <Expression
  expression={body}
  position={position.concat(1)}
/>
{/if}
