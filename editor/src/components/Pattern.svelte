<script>
  import * as Display from "../gen/eyg/editor/display";
  import * as Pattern from "../gen/eyg/ast/pattern";

  // metadata is expression metadata
  export let metadata;
  export let pattern;

  // TODOpattern metadata is the answer here really.
  // TODO do we think about calling this pattern metadata all the way down
  let display = Display.display_pattern(metadata, pattern)
  $: display = Display.display_pattern(metadata, pattern)
</script>

{#if Pattern.is_discard(pattern)}
  <span
    class="border-2 border-transparent outline-none rounded"
    data-editor={Display.marker(display)}
    class:border-indigo-300={Display.is_target(display)}
    >_</span
  >
{:else if Pattern.is_variable(pattern)}
  <span
    class="border-2 border-transparent min-w-10 outline-none rounded required text-blue-500"
    class:border-indigo-300={Display.is_target(display)}
    data-editor={Display.marker(display)}
    >{pattern.label}</span
  >
{:else if Pattern.is_tuple(pattern)}
  <span
    class="border-2 border-transparent outline-none rounded"
    class:border-indigo-300={Display.is_target(display)}
    data-editor={Display.marker(display)}
    >[{#each Display.display_pattern_elements(display, pattern.elements).toArray() as [display, label], i}<span
        class="min-w-10 outline-none border-2 border-transparent rounded text-blue-500"
        class:border-indigo-300={Display.is_target(display)}
        data-editor={Display.marker(display)}>{label}</span
      >{#if i < pattern.elements.toArray().length - 1}
        ,
      {/if}{/each}]</span
  >
{:else}<span
class="border-2 border-transparent outline-none rounded"
class:border-indigo-300={Display.is_target(display)}
data-editor={Display.marker(display)}
>&lbrace;{#each Display.display_pattern_fields(display, pattern.fields).toArray() as [display, display_label, label, display_variable, variable], i}<span
  class="border-2 border-transparent outline-none rounded"
  class:border-indigo-300={Display.is_target(display)}
  data-editor={Display.marker(display)}><span
    class="text-gray-600 border-2 border-transparent outline-none rounded"
    class:border-indigo-300={Display.is_target(display_label)}
    data-editor={Display.marker(display_label)}
      >{label}</span>: <span
      class="text-blue-500 border-2 border-transparent outline-none rounded"
      class:border-indigo-300={Display.is_target(display_variable)}
      data-editor={Display.marker(display_variable)}
        >{variable}</span></span
  >{#if i < pattern.fields.toArray().length - 1}
    ,
  {/if}{/each}&rbrace;</span
>{/if}

<style>
  span.required {
    display: inline-block;
  }
  span:empty.required {
    min-width: 1em;
  }
</style>
