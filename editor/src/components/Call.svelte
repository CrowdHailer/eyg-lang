<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  export let metadata;
  export let function_;
  export let with_;
  export let update_tree;
</script>

<Expression expression={function_} {update_tree} />(<Expression
  expression={with_}
  {update_tree}
/>)
<ErrorNotice type_={metadata.type_} />
