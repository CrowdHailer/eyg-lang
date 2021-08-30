<script>
  import Expression from "./Expression.svelte";
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

  export let pattern;
  export let value;
  export let then;
  export let update_tree;

  function removeLet(path) {
    update_tree(path, then);
  }
  function handleLabelChange({ detail: { content: newLabel } }) {
    console.log("changing");
    if (newLabel != pattern.label) {
      let point = path.concat(count);
      update_tree(
        point,
        Ast.let_({ type: "Variable", label: newLabel }, value, then)
      );
    } else {
    }
  }
</script>

<p>
  <span class="text-yellow-400">let</span>
  {#if pattern.type == "Variable"}
    <TermInput initial={pattern.label} on:change={handleLabelChange} />
  {:else if pattern.type == ""}
    bb{:else}{pattern}{/if} =
  <Expression expression={value} {update_tree} />
</p>
<Expression expression={then} {update_tree} />
