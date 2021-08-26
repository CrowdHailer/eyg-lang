<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";
  import { List } from "../gen/gleam";

  export let update_tree;
  export let path;
  export let count;
  export let type;
  export let then;
  export let error;
  let valueError, thenError;
  $: if (error && error[0].length !== 0) {
    let [first, ...rest] = error[0];
    if (first === 0) {
      valueError = [rest, error[1]];
    } else {
      thenError = [[first - 1, ...rest], error[1]];
    }
  }

  let named, params, variants;
  $: named = type[0];
  $: params = type[1][0];
  $: variants = type[1][1].toArray();

  function handleNameChange({ detail: { content: newName } }) {
    let point = path.concat(count);
    update_tree(point, Ast.name(newName, params, type[1][1], then));
  }
  function handleVariantChange({ detail: { content: newName } }) {
    console.log(newName);
  }
  function handleVariantEnter(event, i) {
    let point = path.concat(count);
    let before = variants.slice(0, i + 1);
    let after = variants.slice(i + 1);
    let newVariants = List.fromArray([
      ...before,
      ["_", Ast.tuple_(List.fromArray([]))],
      ...after,
    ]);
    update_tree(point, Ast.name(named, params, newVariants, then));
  }
</script>

<span class="text-yellow-400">type</span>
<TermInput initial={named} on:change={handleNameChange} /><span
  class="text-gray-600">(</span
><span class="text-gray-600">)</span>
<Indent>
  {#each variants as [variant, { elements }], index}
    <div>
      <TermInput
        initial={variant}
        on:change={handleVariantChange}
        on:enter={(event) => {
          handleVariantEnter(event, index);
        }}
      /><span class="text-gray-600">(</span><TermInput
        initial={elements.toArray().join(", ")}
      /><span class="text-gray-600">)</span>
    </div>
  {/each}
</Indent>
<Expression
  {path}
  count={count + 1}
  tree={then}
  {update_tree}
  error={thenError}
/>
