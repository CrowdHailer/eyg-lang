<script>
  import Expression from "./Expression.svelte";
  export let function_;
  export let with_;
  export let update_tree;
  export let path;
  export let count;
  export let error;

  let func_error;
  $: if (error && error[0].length !== 0) {
    let [first, ...rest] = error[0];
    if (first === 0) {
      func_error = [rest, error[1]];
    } else {
      func_error = undefined;
      console.log("TODO error in args");
    }
  } else {
    func_error = undefined;
  }
</script>

<Expression
  tree={function_}
  path={path.concat(count)}
  count={0}
  {update_tree}
  error={func_error}
/>()
