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
  export let error;
  let valueError, thenError;
  $: if (error && error[0].length !== 0) {
    let [first, ...rest] = error[0];
    if (first === 0) {
      if (value.type == "Let") {
        // do nothing,
      } else {
        // There is an extra zero for being the tail in a let chain
        rest = rest.slice(1);
      }
      valueError = [rest, error[1]];
      thenError = undefined;
    } else {
      thenError = [[first - 1, ...rest], error[1]];
      valueError = undefined;
    }
  } else {
    thenError = undefined;
    valueError = undefined;
  }

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
  <Expression
    tree={value}
    {update_tree}
    path={path?.concat(count)}
    count={0}
    error={valueError}
  />
</p>
<Expression
  tree={then}
  {path}
  count={count + 1}
  {update_tree}
  error={thenError}
/>
