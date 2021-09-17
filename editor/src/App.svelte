<script>
  import { tick } from "svelte";

  import Expression from "./components/Expression.svelte";
  import { replace_node } from "./gen/eyg/ast/transform";
  import * as Typer from "./gen/eyg/typer";
  import * as Codegen from "./gen/eyg/codegen/javascript";
  import * as AstBare from "./gen/eyg/ast";
  import * as Builders from "./gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import { List } from "./gen/gleam";
  import * as Edit from "./gen/eyg/ast/edit";
  import * as Editor from "./gen/eyg/ast/editor";
  import * as example from "./gen/standard/example";
  let untyped = example.simple();
  // let untyped = Ast.hole();
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
    console.warn("do nothing");
    // replace node needs to use untyped because infer fn assumes nil metadata
    // untyped = replace_node(untyped, path, replacement);
  }

  function targetToPosition(target) {
    return target
      .closest("[data-position^=p]")
      .dataset.position.slice(1)
      .split(",")
      .filter((x) => x.length)
      .map((x) => parseInt(x));
  }

  function handleFocusin(event) {
    targetToPosition(event.target);
  }

  function handleKeydown(event) {
    let { key, ctrlKey } = event;
    let position = List.fromArray(targetToPosition(event.target));
    let [a, b] = Editor.handle_keydown(expression, position, key, typer);
    untyped = a;
    // stringify in the gleam code
    position = "p" + b.toArray().join(",");
    tick().then(() => {
      let after = document.querySelector("[data-position='" + position + "']");
      console.log(after);
      after.focus();
    });
  }

  function handleContentedited({ detail: { position, content } }) {
    let [a, b] = Editor.handle_contentedited(expression, position, content);
    console.log(a);
    untyped = a;
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white relative"
  on:click={handleFocusin}
  on:keydown={handleKeydown}
>
  <Expression
    {expression}
    global={{ update_tree, typer }}
    on:contentedited={handleContentedited}
    position={[]}
  />
  <!-- <pre class="my-2 bg-gray-100 p-1">
    {output}
  </pre> -->
</div>
<div class="max-w-4xl mx-auto px-10 py-6">
  <pre>
    {JSON.stringify(untyped, null, 2)}
  </pre>
</div>
