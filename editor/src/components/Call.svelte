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
