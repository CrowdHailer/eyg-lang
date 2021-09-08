<script>
  import Expression from "./Expression.svelte";
  export let metadata;
  export let function_;
  export let with_;
  export let update_tree;
</script>

<Expression {metadata} expression={function_} {update_tree} />(<Expression
  {metadata}
  expression={with_}
  {update_tree}
/>)
{#if metadata.type_.type == "Error"}
  <div class=" bg-red-100 border-t-2 border-red-300 py-1 px-4">
    {JSON.stringify(metadata.type_[0])}
  </div>
{/if}
