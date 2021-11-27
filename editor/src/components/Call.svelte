<script>
  import Expression from "./Expression.svelte";
  export let position;
  export let metadata;
  export let function_;
  export let with_;
</script>

<span tabindex="-1" data-editor={"p:" + position.join(",")}>
  <Expression
    expression={function_}
    position={position.concat(0)}
  />(<Expression expression={with_} position={position.concat(1)} />)
</span>
