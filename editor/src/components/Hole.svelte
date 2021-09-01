<script>
  import { tick } from "svelte";
  import { List } from "../gen/gleam";

  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import * as Pattern from "../gen/eyg/ast/pattern";

  export let metadata;
  export let update_tree;

  let content;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element.focus();
    });
  }

  function insertLet() {
    let path = metadata.path;
    let newNode = Ast.let_(Pattern.variable(""), Ast.hole(), Ast.hole());
    update_tree(path, newNode);
    thenFocus(path);
  }

  function insertVariable(label) {
    label = label.trim().replace(" ", "_");
    let path = metadata.path;
    let newNode = Ast.variable(label);
    update_tree(path, newNode);
    thenFocus(path);
  }

  function insertBinary() {
    let path = metadata.path;
    let newNode = Ast.binary("");
    update_tree(path, newNode);
    thenFocus(path);
  }

  function insertTuple() {
    let path = metadata.path;
    let newNode = Ast.tuple_(List.fromArray([]));
    update_tree(path, newNode);
    thenFocus(Ast.append_path(path, 0));
  }

  function insertFunction() {
    let path = metadata.path;
    let newNode = Ast.function$(List.fromArray([""]), Ast.hole());
    update_tree(path, newNode);
    thenFocus(path);
  }
  // scope should include equal
  //   Need keydown for tab to work
  function handleKeydown(event) {
    if (event.key === "Tab") {
      if (content === "l") {
        event.preventDefault();
        insertLet();
      } else if (content.trim().replace(" ", "_")) {
        event.preventDefault();
        insertVariable(content);
      }
    } else if (event.key === '"') {
      event.preventDefault();
      insertBinary();
    } else if (event.key === "=") {
      event.preventDefault();
      let pattern = content.trim().replace(" ", "_");
      let path = metadata.path;
      let newNode = Ast.let_(Pattern.variable(pattern), Ast.hole(), Ast.hole());
      update_tree(path, newNode);
      thenFocus(Ast.append_path(path, 0));
    } else if (event.key === "[") {
      event.preventDefault();
      insertTuple();
    }
  }
  let nodeFocused = false;
  let helpFocused = false;
  let active = false;
  $: active = nodeFocused || helpFocused;
</script>

<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  id={metadata.path ? "p" + metadata.path.toArray().join(",") : ""}
  contenteditable=""
  bind:textContent={content}
  on:keydown={handleKeydown}
  on:focus={() => (nodeFocused = true)}
  on:blur={() =>
    setTimeout(() => {
      nodeFocused = false;
    }, 0)}
/>
<div
  class:hidden={!active}
  class="my-1 py-1 -mx-2 px-2 bg-yellow-50"
  on:focusin={() => console.log((helpFocused = true))}
  on:blurout={() => {
    console.log("vlur our");

    setTimeout(() => {
      helpFocused = false;
    }, 0);
  }}
>
  <span>variables: </span>
  {#each metadata.scope.toArray() as [key]}
    {#if key !== "" && key !== "$"}
      <button
        class="hover:bg-gray-200 px-1 outline-none focus:border-gray-500 border-b-2 border-gray-100"
        on:click={() => insertVariable(key)}>{key}</button
      >
    {/if}
  {/each}
  <br />
  <span>elements:</span>
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertLet}>Let</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertFunction}>Function</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertBinary}>Binary</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertTuple}>Tuple</button
  >
</div>

<style>
  span {
    display: inline-block;
    min-width: 1em;
  }
</style>
