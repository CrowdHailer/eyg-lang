<script>
  import TermInput from "./TermInput.svelte";

  export let named;
  export let variant;
  export let global;

  function handleVariantChange({ detail: { content: newVariant } }) {
    let point = path.concat([count]);
  }
</script>

<TermInput initial={named} on:change={console.log} />::<TermInput
  initial={variant}
  on:change={handleVariantChange}
/>
