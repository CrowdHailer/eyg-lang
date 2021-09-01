<script>
  import Hole from "./Hole.svelte";
  import * as Ast from "../gen/eyg/ast";
  export let metadata;
  export let update_tree;
  export let generator;
</script>

{#if Ast.is_hole(generator)}
  <Hole {metadata} {update_tree} />
{:else}
  TODO provider
{/if}
