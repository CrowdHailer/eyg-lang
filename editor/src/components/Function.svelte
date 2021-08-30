<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  // export let for_;
  export let body;
  // always tuple
  // for_ = $
  let arguments_;
  $: arguments_ = body[1].pattern.elements.toArray();
  let main = body[1].then;
  console.log(main);
  export let update_tree;
</script>

({arguments_.join(", ")}) <strong>=></strong>
<Indent>
  <Expression expression={main} {update_tree} />
</Indent>
