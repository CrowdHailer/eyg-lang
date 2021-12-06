<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";
  import * as Editor from "../gen/eyg/ast/editor";

  export let metadata;
  export let pattern;
  export let body;

  let multiline = false;
  multiline = Editor.is_multiexpression(body)


</script>

<Pattern {pattern} {metadata} />
<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}>=></span
>
{#if multiline}
<Indent>
  <Expression
    expression={body}
  />
</Indent>
  {:else}
  <Expression
  expression={body}
/>
{/if}
