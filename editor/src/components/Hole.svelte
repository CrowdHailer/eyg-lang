<script>
  import { tick, createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
  import ErrorNotice from "./ErrorNotice.svelte";
  import { List } from "../gen/gleam";

  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import * as Provider from "../gen/eyg/ast/provider";
  import * as Pattern from "../gen/eyg/ast/pattern";

  export let metadata;
  export let update_tree;
  export let required = false;

  let content;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element?.focus();
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
  function insertRow() {
    let path = metadata.path;
    let newNode = Ast.row(List.fromArray([]));
    update_tree(path, newNode);
    thenFocus(Ast.append_path(path, 0));
  }

  function insertFunction() {
    let path = metadata.path;
    let newNode = Ast.function$(List.fromArray([]), Ast.hole());
    update_tree(path, newNode);
    thenFocus(path);
  }

  function insertProvider(content) {
    let path = metadata.path;
    let name = content.trim().replace(" ", "_");
    let newNode = Provider.from_name(name);
    update_tree(path, newNode);
    thenFocus(path);
  }
  // scope should include equal
  //   Need keydown for tab to work
  function handleKeydown(event) {
    if (event.key === "Tab") {
      if (content.trim().replace(" ", "_")) {
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
    } else if (event.key === "(") {
      event.preventDefault();
      let pattern = content.trim().replace(" ", "_");
      let path = metadata.path;
      if (pattern) {
        let newNode = Ast.call(Ast.variable(pattern), List.fromArray([]));
        update_tree(path, newNode);
        thenFocus(Ast.append_path(path, 1));
      } else {
        insertFunction();
      }
    } else if (event.key === "[") {
      event.preventDefault();
      insertTuple();
    } else if (event.key === "{") {
      event.preventDefault();
      insertRow();
    } else if (event.key === "<") {
      event.preventDefault();
      insertProvider(content);
    } else if (event.key === "Backspace" && content === "") {
      console.log("deleting up");
      dispatch("deletebackwards", {});
    }
  }
  let nodeFocused = false;
  let helpFocused = false;
  let active = false;
  $: active = nodeFocused || helpFocused;

  function isDescendant(parent, child) {
    var node = child.parentNode;
    while (node != null) {
      if (node == parent) {
        return true;
      }
      node = node.parentNode;
    }
    return false;
  }

  let helpBox;
  function focusHelp() {
    helpFocused = true;
  }
  function tryBlur() {
    // blurout didn't work
    setTimeout(() => {
      if (!isDescendant(helpBox, window.document.activeElement)) {
        helpFocused = false;
      }
    }, 0);
  }
</script>

<span
  class:required
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  id={metadata.path ? "p" + metadata.path.toArray().join(",") : ""}
  contenteditable=""
  bind:textContent={content}
  on:keydown={handleKeydown}
  on:focus={() => (nodeFocused = true)}
  on:blur={() => {
    setTimeout(() => {
      nodeFocused = false;
    }, 0);
  }}
/>
<div
  class:hidden={!active}
  class="my-1 py-1 -mx-2 px-2 bg-yellow-50"
  bind:this={helpBox}
>
  <span>variables: </span>
  {#each metadata.scope.toArray() as [key]}
    {#if key !== "" && key !== "$"}
      <button
        class="hover:bg-gray-200 px-1 outline-none focus:border-gray-500 border-b-2 border-gray-100"
        on:click={() => insertVariable(key)}
        on:focus={focusHelp}
        on:blur={tryBlur}>{key}</button
      >
    {/if}
  {/each}
  <br />
  <span>elements:</span>
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertLet}
    on:focus={focusHelp}
    on:blur={tryBlur}>Let</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertFunction}
    on:focus={focusHelp}
    on:blur={tryBlur}>Function</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertBinary}
    on:focus={focusHelp}
    on:blur={tryBlur}>Binary</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertTuple}
    on:focus={focusHelp}
    on:blur={tryBlur}>Tuple</button
  >
  <button
    class="hover:bg-gray-200 px-1 font-bold outline-none focus:border-gray-500 border-b-2 border-gray-100"
    on:click={insertRow}
    on:focus={focusHelp}
    on:blur={tryBlur}>Row</button
  >
</div>
<ErrorNotice type_={metadata.type_} />

<style>
  span {
    display: inline-block;
  }
  span.required {
    min-width: 1em;
  }
</style>
