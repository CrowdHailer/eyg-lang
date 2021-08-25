<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";

  export let update_tree;
  export let path;
  export let count;
  export let type;
  export let then;
  let named, params, variants;
  $: named = type[0];
  $: params = type[1][0];
  $: variants = type[1][1].toArray();
</script>

<p>
  <strong>{named}</strong> &lbrace;
</p>
<Indent>
  {#each variants as [variant, { elements }]}
    <span class="text-blue-300">{variant}({elements.toArray().join(", ")})</span
    >
    <br />
  {/each}
</Indent>
&rbrace;
<Expression {path} count={count + 1} tree={then} {update_tree} />
