<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let elements;
  export let update_tree;
</script>

[{#each elements.toArray() as element, i}
  <Expression
    expression={element}
    {update_tree}
    on:pinpoint
    on:depoint
  />,&nbsp;
{/each}]
