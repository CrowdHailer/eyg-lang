<script>
  import Hole from "./Hole.svelte";
  import * as Ast from "../gen/eyg/ast";
  export let metadata;
  export let generator;
  export let config;
</script>

{#if Ast.is_hole(generator)}
  <Hole {metadata} />
{:else}
  --{config}--
{/if}
