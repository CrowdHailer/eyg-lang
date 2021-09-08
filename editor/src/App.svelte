<script>
  import Expression from "./components/Expression.svelte";
  import { replace_node } from "./gen/eyg/ast/transform";
  import { infer, init } from "./gen/eyg/typer";
  import * as Codegen from "./gen/eyg/codegen/javascript";
  import * as AstBare from "./gen/eyg/ast";
  import * as Builders from "./gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import { List } from "./gen/gleam";
  // let untyped = example.code();
  let untyped = Ast.hole();
  let result;
  let expression;
  $: result = infer(untyped, init(List.fromArray([])));
  $: if (result.type == "Error") {
    console.warn("Failed to type");
  }
  $: expression = result[0][0];
  $: typer = result[0][1];
  $: output = Codegen.render_to_string(expression, typer);

  async function update_tree(path, replacement) {
    // replace node needs to use untyped because infer fn assumes nil metadata
    untyped = replace_node(untyped, path, replacement);
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white text-indigo-00"
>
  <Expression {expression} {update_tree} />
  <pre class="my-2 bg-gray-100 p-1">
    {output}
  </pre>
</div>
<!-- {JSON.stringify(untyped)} -->
