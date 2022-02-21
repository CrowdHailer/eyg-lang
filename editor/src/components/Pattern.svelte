<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";
  import * as Pattern from "../../../eyg/build/dev/javascript/eyg/dist/eyg/ast/pattern";

  // Note this is expression metadata the display objects in this file are metadata of type Display
  export let metadata;
  export let pattern;
</script>

{#if Pattern.is_discard(pattern)}
  <span
    class="border-2 border-transparent outline-none rounded"
    data-editor={Display.marker(metadata)}
    class:border-indigo-300={Display.is_target(metadata)}>_</span
  >
{:else if Pattern.is_variable(pattern)}
  <span
    class="border-2 border-transparent min-w-10 outline-none rounded required text-blue-500"
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}>{pattern.label}</span
  >
{:else if Pattern.is_tuple(pattern)}
  <span
    class="border-2 border-transparent outline-none rounded"
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}
    >[{#each Display.display_pattern_elements(metadata, pattern.elements).toArray() as [display, label], i}<span
        class="min-w-10 outline-none border-2 border-transparent rounded text-blue-500"
        class:border-indigo-300={Display.is_target(display)}
        data-editor={Display.marker(display)}>{label}</span
      >{#if i < pattern.elements.toArray().length - 1}
        ,
      {/if}{/each}]</span
  >
{:else}<span
    class="border-2 border-transparent outline-none rounded"
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}
    >&lbrace;{#each Display.display_pattern_fields(metadata, pattern.fields).toArray() as [display, display_label, label, display_variable, variable], i}<span
        class="border-2 border-transparent outline-none rounded"
        class:border-indigo-300={Display.is_target(display)}
        data-editor={Display.marker(display)}
        ><span
          class="text-gray-600 border-2 border-transparent outline-none rounded"
          class:border-indigo-300={Display.is_target(display_label)}
          data-editor={Display.marker(display_label)}>{label}</span
        >:
        <span
          class="text-blue-500 border-2 border-transparent outline-none rounded"
          class:border-indigo-300={Display.is_target(display_variable)}
          data-editor={Display.marker(display_variable)}>{variable}</span
        ></span
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
