<script>
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import Hole from "./Hole.svelte";
  export let metadata;
  export let elements;
  export let update_tree;
</script>

[{#each elements.toArray() as element, i}
  <Expression expression={element} {update_tree} />,&nbsp;
{/each}
<Hole
  metadata={Object.assign({}, metadata, {
    path: Ast.append_path(metadata.path, elements.toArray().length),
  })}
  {update_tree}
/>]
