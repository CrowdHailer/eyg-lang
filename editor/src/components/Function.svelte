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

  let newContent = "";
  function handleKeydown() {}
</script>

({arguments_.join(", ")}<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  contenteditable=""
  bind:textContent={newContent}
  on:keydown={handleKeydown}
/>) <strong>=></strong>
<Indent>
  <Expression expression={main} {update_tree} on:pinpoint on:depoint />
</Indent>
