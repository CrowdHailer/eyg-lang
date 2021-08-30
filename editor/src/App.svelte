<script>
  import Expression from "./components/Expression.svelte";
  import * as example from "./gen/standard/example";

  import { replace_node } from "./gen/eyg/ast/transform";
  import { infer, init } from "./gen/eyg/typer";
  import { List } from "./gen/gleam";
  let untyped = example.code();
  let result;
  let expression;
  $: result = infer(untyped, init(List.fromArray([])));
  $: expression = result[0][0];

  function update_tree(path, replacement) {
    console.log(path, replacement);
    console.log(replacement, "2222");
    // replace node needs to use untyped because infer fn assumes nil metadata
    untyped = replace_node(untyped, path, replacement);
    console.log(untyped);
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

  $: console.log(expression, "laura hi");
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white text-indigo-00"
>
  <Expression {expression} {update_tree} />
</div>
