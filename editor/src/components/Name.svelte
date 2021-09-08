<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import TermInput from "./TermInput.svelte";
  import * as Ast from "../gen/eyg/ast";
  import {
    change_type_name,
    change_variant,
    add_variant,
  } from "../gen/eyg/ast/transform";

  export let update_tree;

  export let type;
  export let then;

  let named, params, variants;
  $: named = type[0];
  $: params = type[1][0].toArray();
  $: variants = type[1][1].toArray();

  function handleNameChange({ detail: { content: newName } }) {
    let point = path.concat(count);
    let node = Ast.name(change_type_name(type, newName), then);
    update_tree(point, node);
  }
  function handleVariantChange({ detail: { content: newName } }, i) {
    let point = path.concat(count);
    let node = Ast.name(change_variant(type, i, newName), then);
    update_tree(point, node);
  }
  function handleVariantEnter(event, i) {
    let point = path.concat(count);
    console.log("t", type, "--", add_variant(type, i, "_"));
    let node = Ast.name(add_variant(type, i, "_"), then);
    console.log(node);
    update_tree(point, node);
  }

  const mappings = {};
  const letters = ["a", "b", "c", "d"];
  let textParams = [];
  $: textParams = params.map((i) => {
    let size = Object.values(mappings).length;
    let letter = letters[size];
    mappings[i] = letter;
    return letter;
  });
</script>

<p>
  <span class="text-yellow-400">type</span>
  <TermInput initial={named} on:change={handleNameChange} /><span
    class="text-gray-600">(</span
  ><span class="text-blue-700">{textParams.join(", ")}</span><span
    class="text-gray-600">)</span
  >
  <Indent>
    {#each variants as [variant, { elements }], index}
      <div>
        <TermInput
          initial={variant}
          on:change={(event) => {
            handleVariantChange(event, index);
          }}
          on:enter={(event) => {
            handleVariantEnter(event, index);
          }}
        /><span class="text-gray-600">(</span><TermInput
          initial={elements
            .toArray()
            .map(({ type, ...rest }) => {
              if (type === "Unbound") {
                return mappings[rest.i];
              } else {
                return "TODO";
              }
            })
            .join(", ")}
        /><span class="text-gray-600">)</span>
      </div>
    {/each}
  </Indent>
</p>
<Expression expression={then} {update_tree} />
