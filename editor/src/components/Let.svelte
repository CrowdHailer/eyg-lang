<script>
  import * as Display from "../gen/eyg/editor/display";

  import Expression from "./Expression.svelte";
  import Pattern from "./Pattern.svelte";
  import Indent from "./Indent.svelte";

  export let metadata;
  export let pattern;
  export let value;
  export let then;

  let multiline = false;
  $: multiline = Display.is_multiexpression(value);

  let expand = false;
  $: expand = Display.show_value(metadata);

  let pattern_display = Display.display_pattern(metadata, pattern);
  $: pattern_display = Display.display_pattern(metadata, pattern);
</script>

<p
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
>
  <span class="text-gray-500">let</span>
  <Pattern {pattern} metadata={pattern_display} />
  {#if !value[1].body}
    =
  {/if}
  {#if multiline}
    {#if expand}
      <Indent>
        <Expression expression={value} />
      </Indent>
    {:else}
      <span class="text-gray-500" data-editor="{Display.marker(metadata)},1"
        >&lbrace; ... &rbrace;</span
      >
    {/if}
  {:else}
    <Expression expression={value} />
  {/if}
</p>
<Expression expression={then} />
