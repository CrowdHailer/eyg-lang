<script>
  import Expression from "./Expression.svelte";
  export let function_;
  export let with_;
</script>

<Expression tree={function_} />()
