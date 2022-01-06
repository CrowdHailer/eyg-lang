<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";

  export let metadata;
  export let pattern;
  export let body;

  let multiline = false;
  $: multiline = Display.is_multiexpression(body);

  let expand = false;
  $: expand = Display.show_expression(metadata);

  let pattern_display = Display.display_pattern(metadata, pattern);
  $: pattern_display = Display.display_pattern(metadata, pattern);
</script>

<Pattern {pattern} metadata={pattern_display} />
<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}>=></span
>
{#if multiline}
  {#if expand}
    <Indent>
      <Expression expression={body} />
    </Indent>
  {:else}
    <span class="text-gray-500" data-editor="{Display.marker(metadata)},1"
      >&lbrace; ... &rbrace;</span
    >{/if}
{:else}
  <Expression expression={body} />
{/if}
