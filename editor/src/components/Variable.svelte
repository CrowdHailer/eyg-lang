<script>
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

  export let metadata;
  export let label;
  export let update_tree;
  function handleChange({ detail: { content: newLabel } }) {
    let node = Ast.variable(newLabel);
    console.log(node);
    update_tree(metadata.path, node);
  }
</script>

<!-- {JSON.stringify(metadata.scope.toArray())} -->
<TermInput initial={label} path={metadata.path} on:change={handleChange} />
<!-- <span id="p{metadata.path.toArray().join(',')}">
  {label}
</span> -->
