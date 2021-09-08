<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let metadata;
  export let fields;
  export let global;
</script>

<Indent>
  {#each fields.toArray() as [label, value], i}
    <span class="text-gray-400">{label}</span><span class="text-gray-500"
      >:</span
    >
    <Expression expression={value} {global} /><br />
  {/each}
</Indent>
<ErrorNotice type_={metadata.type_} />
