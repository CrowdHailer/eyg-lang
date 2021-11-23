<script>
  import { tick } from "svelte";
  import * as Ast from "../gen/eyg/ast";
  import * as Pattern from "../gen/eyg/ast/pattern";
  import { List } from "../gen/gleam";

  export let position;
  export let metadata;
  export let pattern;
  export let global;
</script>

<!-- Bubble everything to the top does an onchange event bubble -->

{#if Pattern.is_discard(pattern)}
  <span
    tabindex="-1"
    data-position={"p" + position.join(",")}
    class="border-2 border-white focus:border-indigo-300 outline-none rounded"
    >_</span
  >
{:else if Pattern.is_variable(pattern)}
  <!-- add a p0 on the end of the id tree -->
  <!-- bubble event out from here -->
  <!-- Think more about tope level everything BUT that means we need to capture key presses for editing variables and binary -->
  <span
    tabindex="-1"
    data-position={"p" + position.join(",")}
    class="border-b border-white min-w-10 outline-none focus:border-gray-900 focus:border-2 required"
    >{pattern.label}</span
  >
{:else if Pattern.is_tuple(pattern)}
  <span
    tabindex="-1"
    data-position={"p" + position.join(",")}
    class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
    >[{#each pattern.elements.toArray() as element, i}<span
        tabindex="-1"
        class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
        data-position={"p" + position.concat(i).join(",")}>{element}</span
      >{#if i < pattern.elements.length - 1}
        ,
      {/if}
    {/each}]</span
  >
{:else}{JSON.stringify(pattern)}{/if}

<style>
  span.required {
    display: inline-block;
  }
  span:empty.required {
    min-width: 1em;
  }
</style>
