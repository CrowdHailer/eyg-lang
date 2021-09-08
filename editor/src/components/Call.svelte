<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  export let metadata;
  export let function_;
  export let with_;
  export let global;
</script>

<Expression expression={function_} {global} />(<Expression
  expression={with_}
  {global}
/>)
<ErrorNotice type_={metadata.type_} />
