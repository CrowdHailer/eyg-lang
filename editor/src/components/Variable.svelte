<script>
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

  export let metadata;
  export let label;
  export let update_tree;
  function handleChange({ detail: { content: newLabel } }) {
    if (newLabel !== label) {
      let node = Ast.variable(newLabel);
      console.log(node);
      update_tree(metadata.path, node);
    }
  }
</script>

<!-- {JSON.stringify(metadata.type_)} -->
<!-- {JSON.stringify(metadata.scope.toArray())} -->
<TermInput initial={label} path={metadata.path} on:change={handleChange} />
<!-- <span id="p{metadata.path.toArray().join(',')}">
  {label}
</span> -->
{#if metadata.type_.type == "Error"}
  <div class=" bg-red-100 border-t-2 border-red-300 py-1 px-4">
    Unknown variable {label}
  </div>
{/if}
