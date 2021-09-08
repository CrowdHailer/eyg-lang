<script>
  import Expression from "./Expression.svelte";
  export let function_;
  export let with_;
  export let update_tree;
</script>

<Expression expression={function_} {update_tree} />()
