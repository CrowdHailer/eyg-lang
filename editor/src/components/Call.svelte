<script>
  import Expression from "./Expression.svelte";
  export let position;
  export let metadata;
  export let function_;
  export let with_;
  export let global;
</script>

<span tabindex="-1" data-editor={"p:" + position.join(",")}>
  <Expression
    expression={function_}
    {global}
    position={position.concat(0)}
  />(<Expression expression={with_} {global} position={position.concat(1)} />)
</span>
