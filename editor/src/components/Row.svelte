<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let metadata;
  export let fields;
  export let update_tree;
</script>

<Indent>
  {#each fields.toArray() as [label, value], i}
    <span class="text-gray-400">{label}</span><span class="text-gray-500"
      >:</span
    >
    <Expression expression={value} {update_tree} /><br />
  {/each}
</Indent>
<ErrorNotice type_={metadata.type_} />
