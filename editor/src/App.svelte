<script>
  import Expression from "./components/Expression.svelte";
  import * as boolean from "./gen/standard/boolean";
  let tree = boolean.code();
  import { replace_node } from "./gen/eyg/ast/transform";
  import { infer, init } from "./gen/eyg/typer";
  import { List } from "./gen/gleam";

  let result = "Ok";
  let message;

  function update_tree(path, replacement) {
    tree = replace_node(tree, List.fromArray(path), replacement);
    let output = infer(tree, init(List.fromArray([])));
    result = output.type;
    message = output[0];
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white text-indigo-00"
>
  <Expression {tree} path={[]} count={0} {update_tree} />
</div>
{#if result == "Error"}
  {JSON.stringify(message)}
{/if}
