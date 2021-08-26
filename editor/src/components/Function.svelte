<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let for_;
  export let body;
  // always tuple
  // for_ = $
  let arguments_;
  $: arguments_ = body.pattern.elements.toArray();
  let main = body.then;
  export let update_tree;
  export let path;
  export let count;
</script>

({arguments_.join(", ")}) <strong>=></strong>
<Indent>
  <Expression tree={main} path={path.concat(count)} count={0} {update_tree} />
</Indent>
