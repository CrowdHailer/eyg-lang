<script>
  import Expression from "./Expression.svelte";
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";

  export let metadata;
  export let pattern;
  export let value;
  export let then;
  export let update_tree;

  function handleLabelChange({ detail: { content: newLabel } }) {
    if (newLabel != pattern.label) {
      update_tree(
        metadata.path,
        Ast.let_({ type: "Variable", label: newLabel }, value, then)
      );
    } else {
    }
  }
</script>

<p>
  <span class="text-yellow-400">let</span>
  {#if pattern.type == "Variable"}
    <TermInput
      initial={pattern.label}
      on:change={handleLabelChange}
      path={metadata.path}
    />
  {:else if pattern.type == ""}
    bb{:else}{pattern}{/if} =
  <Expression expression={value} {update_tree} on:pinpoint on:depoint />
</p>
<Expression expression={then} {update_tree} on:pinpoint on:depoint />
