<script>
  import Hole from "./Hole.svelte";
  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  export let position;
  export let metadata;
  export let generator;
  export let config;
</script>

{#if Ast.is_hole(generator)}
  <Hole {position} {metadata} />
{:else}
  --{config}--
{/if}
