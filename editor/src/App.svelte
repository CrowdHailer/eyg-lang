<script>
  import Expression from "./components/Expression.svelte";
  import { replace_node } from "./gen/eyg/ast/transform";
  import * as Typer from "./gen/eyg/typer";
  import * as Codegen from "./gen/eyg/codegen/javascript";
  import * as AstBare from "./gen/eyg/ast";
  import * as Builders from "./gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import { List } from "./gen/gleam";
  // let untyped = example.code();
  let untyped = Ast.hole();
  let expression;
  let output;
  let typer;
  $: (() => {
    let temp = Typer.infer_unconstrained(untyped);
    expression = temp[0];
    // console.log(expression);
    typer = temp[1];
    try {
      output = Codegen.render_to_string(expression, typer);
    } catch (error) {
      console.error(error);
    }
  })();

  async function update_tree(path, replacement) {
    // replace node needs to use untyped because infer fn assumes nil metadata
    untyped = replace_node(untyped, path, replacement);
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white relative">
  <Expression {expression} global={{ update_tree, typer }} />
  <pre class="my-2 bg-gray-100 p-1">
    {output}
  </pre>
</div>
