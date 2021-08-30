<script>
  import Expression from "./components/Expression.svelte";
  import * as example from "./gen/standard/example";

  import { replace_node } from "./gen/eyg/ast/transform";
  import { infer, init } from "./gen/eyg/typer";
  import { List } from "./gen/gleam";
  let result = infer(example.code(), init(List.fromArray([])));
  let [expression, tree] = result[0];
  // let result = "Ok";
  let error;

  function update_tree(path, replacement) {
    // expression = replace_node(expression, List.fromArray(path), replacement);
    // let output = infer(expression, init(List.fromArray([])));
    // result = output.type;
    // if (result == "Error") {
    //   let message = output[0][0];
    //   let location = output[0][1].location.toArray();
    //   error = [location, message];
    // } else {
    //   error = undefined;
    // }
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white text-indigo-00"
>
  <Expression {expression} {update_tree} {error} />
</div>
