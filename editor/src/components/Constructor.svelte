<script>
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";
  import ErrorNotice from "./ErrorNotice.svelte";

  export let named;
  export let variant;
  export let global;

  function handleVariantChange({ detail: { content: newVariant } }) {
    let point = path.concat([count]);
    global.update_tree(point, Ast.constructor(named, newVariant));
  }
</script>

<TermInput initial={named} on:change={console.log} />::<TermInput
  initial={variant}
  on:change={handleVariantChange}
/>
<ErrorNotice type_={metadata.type_} />
