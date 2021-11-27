<script>
  import Expression from "./Expression.svelte";
  import Pattern from "./Pattern.svelte";

  export let position;
  export let metadata;
  export let pattern;
  export let value;
  export let then;
</script>

<p
  tabindex="-1"
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  data-editor={"p:" + position.join(",")}
>
  <span class="text-yellow-400">let</span>
  <Pattern
    {pattern}
    {metadata}
    position={position.concat(0)}
  />
  =
  <Expression
    expression={value}
    position={position.concat(1)}
  />
</p>
<Expression
  expression={then}
  position={position.concat(2)}
/>
