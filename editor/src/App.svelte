<script>
  import { tick } from "svelte";

  import Expression from "./components/Expression.svelte";
  import * as Typer from "./gen/eyg/typer";
  import * as AstBare from "./gen/eyg/ast";
  import * as Builders from "./gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import { List } from "./gen/gleam";
  import * as Editor from "./gen/eyg/ast/editor";
  import * as example from "./gen/standard/example";
  let [expression, typer] = Typer.infer_unconstrained(example.simple());
  let type = "";
  let scope;
  let generated;


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
    if (event.metaKey) {
      return true
    }
    let { key, ctrlKey } = event;
    let position = List.fromArray(targetToPosition(event.target));
    let state = Editor.handle_keydown(expression, position, key, ctrlKey, typer);
    expression = state.tree
    typer = state.typer
    type = state.type_
    scope = state.scope
    generated = state.generated
    // TODO stringify in the gleam code
    position = "p" + state.position.toArray().join(",");
    tick().then(() => {
      let after = document.querySelector("[data-position='" + position + "']");
      if (after) {
        after.focus();
      } else {
        console.error("Action had no effect, was not able to focus cursor")
      }
    });
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
    global={{ typer }}
    position={[]}
  />
  <div class="sticky bottom-0 bg-white py-2">
    <p>type: {type}</p>
    <nav>variables:
      {#if scope}

      {#each scope.toArray() as v}
        <span class="m-1 p-1 bg-blue-100 rounded">{v}</span>
      {/each}
      {/if}
    </nav>
  </div>
</div>
<pre class="max-w-4xl mx-auto my-2 bg-gray-100 p-1">
  {generated}
</pre>
