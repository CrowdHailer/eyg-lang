<script>
  import Expression from "./components/Expression.svelte";
  import * as boolean from "./gen/standard/boolean";
  let tree = boolean.code();
</script>

<div class="bg-black text-white pl-4 py-4">
  <Expression {tree} />
</div>
