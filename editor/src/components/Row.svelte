<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let fields;
  export let update_tree;
  export let path;
  export let count;
</script>

&lbrace; <br />

<Indent>
  {#each fields.toArray() as [label, value], i}
    <span class="text-gray-400">{label}</span><span class="text-gray-500"
      >:</span
    >
    <Expression
      tree={value}
      path={path.concat(count)}
      count={i}
      {update_tree}
    /><br />
  {/each}
</Indent>
&rbrace;
