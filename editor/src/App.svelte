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
  let position = []
  let type = "";
  let scope;
  let generated;


  function targetToPosition(target) {
    let array = target
    .closest("[data-position^=p]")
    .dataset.position.slice(1)
    .split(",")
    .filter((x) => x.length)
    .map((x) => parseInt(x));
    return List.fromArray(array)
  }

  function handleFocusin(event) {
    console.log("Focusin");
    position = targetToPosition(event.target);
    let [a, b] = Editor.handle_focus(expression, position, typer)
    type = a;
    scope = b
  }

  function handleKeydown(event) {
    if (event.metaKey) {
      return true
    }
    let { key, ctrlKey } = event;
    // TODO check that this is
    let p = targetToPosition(event.target);
    if (p.toArray().join() != position.toArray().join()) {
      console.log(p, position);
      throw "BADDDDD position"
    }
    if (!position) {
      console.log(event);
    }
    // TODO keep editor state around
    let state = Editor.handle_keydown(expression, position, key, ctrlKey, typer);
    expression = state.tree
    typer = state.typer
    console.log("positin", state.position.toArray().join(","));
    position = state.position
    type = state.type_
    scope = state.scope
    generated = state.generated
    // TODO stringify in the gleam code
    let pString = "p" + position.toArray().join(",");
    tick().then(() => {
      let after = document.querySelector("[data-position='" + pString + "']");
      if (after) {
        after.focus();
      } else {
        console.error("Action had no effect, was not able to focus cursor")
      }
    });
  }

  function handleVariableClick(event) {
    event.stopPropagation()
    let label = event.target.closest("[data-variable]").dataset.variable
    console.log(label)
    console.log(position.toArray())
    let state = Editor.place_variable(expression, position, label)
    expression = state.tree
    typer = state.typer
    position = state.position
    type = state.type_
    scope = state.scope
    generated = state.generated
    // TODO stringify in the gleam code
    let pString = "p" + position.toArray().join(",");
    tick().then(() => {
      let after = document.querySelector("[data-position='" + pString + "']");
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
  <!-- Have handle focusin global because we control everything onvce focus. -->
  <!-- but we need to capture key strokes on buttons -->
  <div class="sticky bottom-0 bg-white py-2">
    {#if position.toArray}

    <p>{position.toArray().join(",")}</p>
    {/if}
    <p>type: {type}</p>
    <nav on:click={handleVariableClick}>variables:
      {#if scope}
      {#each scope.toArray() as v}
        <button data-variable={v} class="m-1 p-1 bg-blue-100 rounded">{v}</button>
      {/each}
      {/if}
    </nav>
  </div>
</div>
<pre class="max-w-4xl mx-auto my-2 bg-gray-100 p-1">
  {generated}
</pre>
