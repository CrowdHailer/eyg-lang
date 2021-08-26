<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let named;
  export let value;
  export let clauses;
  export let update_tree;
  export let path;
  export let count;
</script>

<span class="text-yellow-400" title={named}>case</span>
<Expression tree={value} path={path?.concat(count)} count={0} {update_tree} />
<Indent>
  {#each clauses.toArray() as [variant, _variable, then], i}
    {variant}({then.pattern.elements.toArray().join(", ")})
    <span class="font-bold">=></span>
    <Expression
      tree={then.then}
      path={path?.concat(count)}
      count={i + 1}
      {update_tree}
    /><br />
  {/each}
</Indent>
