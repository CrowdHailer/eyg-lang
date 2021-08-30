<script>
  import Expression from "./components/Expression.svelte";
  import * as example from "./gen/standard/example";

  import { replace_node } from "./gen/eyg/ast/transform";
  import { infer, init } from "./gen/eyg/typer";
  import * as AstBare from "./gen/eyg/ast";
  import * as Builders from "./gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import * as Pattern from "./gen/eyg/ast/pattern";
  import { List } from "./gen/gleam";
  // let untyped = example.code();
  let untyped = Ast.provider(function () {
    alert("provider");
  }, 999);
  let result;
  let expression;
  $: result = infer(untyped, init(List.fromArray([])));
  $: expression = result[0][0];

  function update_tree(path, replacement) {
    // replace node needs to use untyped because infer fn assumes nil metadata
    untyped = replace_node(untyped, path, replacement);
  }
  let path;
  let expired = false;
  function handlePinpoint({ detail }) {
    const { metadata, node, current } = detail;
    expired = false;
    path = metadata.path;
  }
  function handleDepoint({}) {
    expired = true;
    // bluring immediatly closes the menu so it cant be clicked on.
    setTimeout(() => {
      if (expired) {
        path = undefined;
      }
      console.log(expired);
    }, 0);
  }
  let current = Ast.provider(() => {}, 999);
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white text-indigo-00"
>
  <Expression
    {expression}
    {update_tree}
    on:pinpoint={handlePinpoint}
    on:depoint={handleDepoint}
  />

  {#if path !== undefined}
    <nav
      class="mt-4"
      on:focusin={() => {
        console.log("menu");
        expired = false;
      }}
    >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() => {
          update_tree(
            path,
            Ast.let_(Pattern.variable("new"), current, current)
          );
          path = undefined;
        }}>Let</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() => {
          update_tree(path, Ast.function$(List.fromArray(["arg1"]), current));
          path = undefined;
        }}>Function</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() => update_tree(path, Ast.binary(""))}>Binary</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() =>
          update_tree(path, Ast.tuple_(List.fromArray([current])))}
        >Tuple</button
      >
    </nav>
    {JSON.stringify(path?.toArray())}
  {/if}
</div>
