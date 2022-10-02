<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";
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
  data-ui={Display.marker(metadata)}>=></span
>
{#if multiline}
  <Indent>
    <Expression expression={body} />
  </Indent>
{:else if body[1].value === "EYG_SPECIAL_COLLAPSE_VALUE"}
  <span class="text-gray-500" data-ui={Display.collapse_marker(metadata)}
    >&lbrace; ... &rbrace;</span
  >
{:else}
  <Expression expression={body} />
{/if}
