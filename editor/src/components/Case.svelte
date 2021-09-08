<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import TermInput from "./TermInput.svelte";
  export let metadata;
  export let named;
  export let value;
  export let clauses;
  export let update_tree;
</script>

<span class="text-yellow-400" title={named}
  >case <TermInput initial={named} /></span
>
<Expression expression={value} {update_tree} />
<ErrorNotice type_={metadata.type_} />
<Indent>
  {#each clauses.toArray() as [variant, _variable, then], i}
    {variant}({then[1].pattern.elements.toArray().join(", ")})
    <span class="font-bold">=></span>
    <Expression expression={then[1].then} {update_tree} /><br />
  {/each}
</Indent>
