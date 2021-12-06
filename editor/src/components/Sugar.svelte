<script>
  import * as Display from "../gen/eyg/editor/display";
  import * as Sugar from "../gen/eyg/ast/sugar";

  import Expression from "./Expression.svelte";

  export let metadata;
  export let sugar;
</script>

{#if sugar instanceof Sugar.UnitVariant}
  <p
    class="border-2 border-transparent outline-none rounded"
    class:border-red-500={metadata.errored && !Display.is_target(metadata)}
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}
  >
    <span class="text-gray-500">name</span>
    <span
      class="text-blue-800 border-2 border-transparent outline-none rounded"
      class:border-red-500={metadata.errored && !Display.is_target(metadata)}
      class:border-indigo-300={Display.is_target(metadata)}>{sugar.label}</span
    >
  </p>
  <Expression expression={sugar.then} />
{:else if sugar instanceof Sugar.TupleVariant}
  <p
    class="border-2 border-transparent outline-none rounded"
    class:border-red-500={metadata.errored && !Display.is_target(metadata)}
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}
  >
    <span class="text-gray-500">name</span>
    <span
      class="text-blue-800 border-2 border-transparent outline-none rounded"
      class:border-red-500={metadata.errored && !Display.is_target(metadata)}
      class:border-indigo-300={Display.is_target(metadata)}
      >{sugar.label}({sugar.parameters.toArray()})</span
    >
  </p>
  <Expression expression={sugar.then} />
{/if}
