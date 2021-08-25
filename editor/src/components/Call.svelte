<script>
  import Expression from "./Expression.svelte";
  export let function_;
  export let with_;
  export let update_tree;
  export let path;
  export let count;
</script>

<Expression
  tree={function_}
  path={path.concat(count)}
  count={0}
  {update_tree}
/>()
