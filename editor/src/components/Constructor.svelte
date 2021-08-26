<script>
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

  export let named;
  export let variant;
  export let update_tree;
  export let path;
  export let count;
  function handleVariantChange({ detail: { content: newVariant } }) {
    let point = path.concat([count]);
    update_tree(point, Ast.constructor(named, newVariant));
  }
</script>

<TermInput initial={variant} on:change={handleVariantChange} />
