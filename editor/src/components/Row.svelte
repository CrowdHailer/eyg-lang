<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";

  export let metadata;
  export let fields;

  let multiline = false;
</script>

<span
class="border-2 border-transparent outline-none rounded"
class:border-red-500={metadata.errored && !Display.is_target(metadata)}
class:border-indigo-300={Display.is_target(metadata)}
data-editor={Display.marker(metadata)}><Indent {multiline}>
  {#each Display.display_expression_fields(metadata, fields).toArray() as [display, label_display, label, value], i}
    <span
      class="border-2 border-transparent outline-none rounded"
      class:border-red-500={display.errored && !Display.is_target(display)}
      class:border-indigo-300={Display.is_target(display)}
      data-editor={Display.marker(display)}>
      <span
        class="text-gray-500 border-2 border-transparent outline-none rounded"
        class:border-red-500={label_display.errored && !Display.is_target(label_display)}
        class:border-indigo-300={Display.is_target(label_display)}
        data-editor={Display.marker(label_display)}
        >{label}:</span>
    </span>
    <Expression expression={value} />{#if i < fields.toArray().length - 1},{#if multiline}<br />{/if}{/if}
  {/each}
</Indent></span>
