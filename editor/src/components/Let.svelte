<script>
  import Expression from "./Expression.svelte";
  export let pattern;
  export let value;
  export let then;
</script>

<p>
  <span class="text-yellow-400">let</span>
  {#if pattern.type == "Variable"}
    {pattern.label}
  {:else if pattern.type == ""}
    bb{:else}{pattern}{/if} = <Expression tree={value} />
</p>
<Expression tree={then} />
