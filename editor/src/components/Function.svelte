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
</script>

({arguments_.join(", ")}) <strong>=></strong> &lbrace;
<Indent>
  <Expression tree={main} />
</Indent>
&rbrace;
