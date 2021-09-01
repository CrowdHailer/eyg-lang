<script>
  import { tick } from "svelte";

  import Expression from "./components/Expression.svelte";
  import * as example from "./gen/standard/example";

  import { replace_node } from "./gen/eyg/ast/transform";
  import { infer, init } from "./gen/eyg/typer";
  import * as AstBare from "./gen/eyg/ast";
  import * as Builders from "./gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import * as Transform from "./gen/eyg/ast/transform";
  import * as Pattern from "./gen/eyg/ast/pattern";
  import { List } from "./gen/gleam";
  // let untyped = example.code();
  let untyped = Ast.hole();
  let result;
  let expression;
  $: result = infer(untyped, init(List.fromArray([])));
  $: expression = result[0][0];

  async function update_tree(path, replacement) {
    // replace node needs to use untyped because infer fn assumes nil metadata
    untyped = replace_node(untyped, path, replacement);
    // await tick();
    // let pathId = "p" + path.toArray().join(",");
    // let element = document.getElementById(pathId);
    // element.focus();
    // setTimeout(function () {
    //   element.setSelectionRange(0, 100);
    // }, 100);
  }
  let metadata;
  let current;
  let expired = false;
  function handlePinpoint({ detail }) {
    // const { metadata, node, current } = detail;
    expired = false;
    metadata = detail.metadata;
    current = detail.current;
  }
  function handleDepoint({ detail }) {
    current = detail.current;

    expired = true;
    // bluring immediatly closes the menu so it cant be clicked on.
    setTimeout(() => {
      if (expired) {
        metadata = undefined;
      }
      console.log(expired);
    }, 0);
  }
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

  {#if false}
    <nav
      class="mt-4"
      on:focusin={() => {
        console.log("menu");
        expired = false;
      }}
    >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={async () => {
          let replacement = Transform.new_type_name("", current);
          let p = metadata.path;
          update_tree(p, replacement);
          metadata = undefined;
        }}>Type</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() => {
          console.log(current, "current");

          update_tree(
            metadata.path,
            Ast.let_(
              Pattern.variable("new"),
              current,
              Ast.provider(function () {
                alert("provider");
              }, 999)
            )
          );
          metadata = undefined;
        }}>Let</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() => {
          update_tree(
            metadata.path,
            Ast.function$(List.fromArray(["arg1"]), current)
          );
          metadata = undefined;
        }}>Function</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() => {
          update_tree(metadata.path, Ast.binary(""));
          metadata = undefined;
        }}>Binary</button
      >
      <button
        class="hover:bg-gray-200 py-1 px-2 border rounded"
        on:click={() =>
          update_tree(metadata.path, Ast.tuple_(List.fromArray([current])))}
        >Tuple</button
      >
      <hr />
      {#each metadata.scope.toArray() as [key]}
        <button
          class="hover:bg-gray-200 py-1 px-2 border rounded"
          on:click={() => update_tree(metadata.path, Ast.variable(key))}
          >{key}</button
        >
      {/each}
    </nav>
    {JSON.stringify(metadata.path?.toArray())}
  {/if}
</div>
{JSON.stringify(untyped)}
