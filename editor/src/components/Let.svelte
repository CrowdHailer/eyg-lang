<script>
  import Expression from "./Expression.svelte";
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

  export let pattern;
  export let value;
  export let then;
  export let update_tree;
  export let path;
  export let count;

  function removeLet(path) {
    update_tree(path, then);
  }
  function handleLabelChange({ detail: { content: newLabel } }) {
    let point = path.concat(count);
    update_tree(
      point,
      Ast.let_({ type: "Variable", label: newLabel }, value, then)
    );
  }
</script>

<p>
  <span class="text-yellow-400" on:click={() => removeLet(path.concat(count))}
    >let</span
  >
  {#if pattern.type == "Variable"}
    <TermInput initial={pattern.label} on:change={handleLabelChange} />
  {:else if pattern.type == ""}
    bb{:else}{pattern}{/if} =
  <Expression tree={value} {update_tree} path={path?.concat(count)} count={0} />
</p>
<Expression tree={then} {path} count={count + 1} {update_tree} />
