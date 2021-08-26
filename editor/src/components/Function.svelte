<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  // export let for_;
  export let body;
  // always tuple
  // for_ = $
  let arguments_;
  $: arguments_ = body.pattern.elements.toArray();
  let main = body.then;
  export let update_tree;
  export let path;
  export let count;
  export let error;

  let innerError;
  // minus 1 to take away matching $ in fn def
  $: if (error && error[0].length !== 0) {
    let [first, ...rest] = error[0];
    innerError = [[first - 1, ...rest], error[1]];
  }
</script>

({arguments_.join(", ")}) <strong>=></strong>
<Indent>
  <Expression
    tree={main}
    path={path.concat(count)}
    count={0}
    {update_tree}
    error={innerError}
  />
</Indent>
