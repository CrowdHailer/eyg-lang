<script>
    import * as Display from "../gen/eyg/editor/display";

  import Expression from "./Expression.svelte";
  import Pattern from "./Pattern.svelte";
  import * as Editor from "../gen/eyg/ast/editor";
  import Indent from "./Indent.svelte";

  export let metadata;
  export let pattern;
  export let value;
  export let then;

  let multiline = false;
  // TODO move to display
  multiline = Editor.is_multiexpression(value)

  // Display.display_pattern(metadata, pattern) then use instance of


// passing around editor gives us all the config like display options
  // [selected, pattern_selection, value_selection, then_selection] = Editor.let_selected(path, editor.selection)

  // metadata.marker
  // metadata.target
  // need metadata.position so that we can create it for the pattern
</script>

<p
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
>
  <span class="text-gray-500">let</span>
  <Pattern
    {pattern}
    {metadata}
  />
  {#if !value[1].body}
  =
  {/if}
  {#if multiline}
  <Indent>
    <Expression
      expression={value}
    />
  </Indent>
  {:else}
  <Expression
    expression={value}
  />
  {/if}
</p>
<Expression
  expression={then}
/>
