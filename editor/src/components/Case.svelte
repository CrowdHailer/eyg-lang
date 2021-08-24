<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let named;
  export let value;
  export let clauses;
</script>

<span class="text-yellow-400" title={named}>case</span>
<Expression tree={value} /> &lbrace;
<Indent>
  {#each clauses.toArray() as [variant, _variable, then]}
    {variant}({then.pattern.elements.toArray().join(", ")})
    <span class="font-bold">=></span>
    <Expression tree={then.then} /><br />
  {/each}
</Indent>
&rbrace;
