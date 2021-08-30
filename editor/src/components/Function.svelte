<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  // export let for_;
  export let body;
  export let update_tree;
  // always tuple
  // for_ = $
  let arguments_;
  let main;
  $: arguments_ = body[1].pattern.elements.toArray();
  $: main = body[1].then;
</script>

({arguments_.join(", ")}) <strong>=></strong>
<Indent>
  <Expression expression={main} {update_tree} on:pinpoint on:depoint />
</Indent>
