<script>
  import * as Pattern from "../gen/eyg/ast/pattern";

  export let position;
  export let metadata;
  export let pattern;
</script>

<!-- Bubble everything to the top does an onchange event bubble -->

{#if Pattern.is_discard(pattern)}
  <span
    tabindex="-1"
    data-editor={"p:" + position.join(",")}
    class="border-2 border-white focus:border-indigo-300 outline-none rounded"
    >_</span
  >
{:else if Pattern.is_variable(pattern)}
  <!-- add a p0 on the end of the id tree -->
  <!-- bubble event out from here -->
  <!-- Think more about tope level everything BUT that means we need to capture key presses for editing variables and binary -->
  <span
    tabindex="-1"
    data-editor={"p:" + position.join(",")}
    class="border-2 border-white min-w-10 outline-none focus:border-indigo-300 rounded focus:border-2 required text-blue-500"
    >{pattern.label}</span
  >
{:else if Pattern.is_tuple(pattern)}
  <span
    tabindex="-1"
    data-editor={"p:" + position.join(",")}
    class="border-2 border-white focus:border-indigo-300 outline-none rounded"
    >[{#each pattern.elements.toArray() as element, i}<span
        tabindex="-1"
        class="min-w-10 outline-none border-2 border-white focus:border-indigo-300 rounded text-blue-500"
        data-editor={"p:" + position.concat(i).join(",")}>{element[0] || "_"}</span
      >{#if i < pattern.elements.toArray().length - 1}
        ,
      {/if}{/each}]</span
  >
{:else}<span
tabindex="-1"
data-editor={"p:" + position.join(",")}
class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
>&lbrace;{#each pattern.fields.toArray() as [label, variable], i}<span
    tabindex="-1"
    class=""
    data-editor={"p:" + position.concat(i).join(",")}><span
      class="text-gray-600 border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100"
      tabindex="-1"
      data-editor={"p:" + position.concat(i, 0).join(",")}
      >{label}</span>: <span
        class="text-blue-500 border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100"
        tabindex="-1"
        data-editor={"p:" + position.concat(i, 1).join(",")}
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
