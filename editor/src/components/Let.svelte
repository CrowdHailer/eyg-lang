<script>
  import Expression from "./Expression.svelte";
  export let pattern;
  export let value;
  export let then;
  export let update_tree;
  export let path;
  export let count;

  function removeLet(path) {
    update_tree(path, then);
  }
</script>

<p>
  <span class="text-yellow-400" on:click={() => removeLet(path.concat(count))}
    >let</span
  >
  {#if pattern.type == "Variable"}
    {pattern.label}
  {:else if pattern.type == ""}
    bb{:else}{pattern}{/if} = <Expression
    tree={value}
    {update_tree}
    path={path?.concat(count)}
    count={0}
  />
</p>
<Expression tree={then} {path} count={count + 1} {update_tree} />
