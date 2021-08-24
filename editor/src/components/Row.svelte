<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  export let fields;
</script>

&lbrace; <br />

<Indent>
  {#each fields.toArray() as [label, value]}
    <span class="text-gray-400">{label}</span><span class="text-gray-500"
      >:</span
    >
    <Expression tree={value} /><br />
  {/each}
</Indent>
&rbrace;
