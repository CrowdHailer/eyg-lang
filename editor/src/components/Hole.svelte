<script>
  import { tick } from "svelte";
  import { List } from "../gen/gleam";

  import * as Ast from "../gen/eyg/ast";
  import * as Pattern from "../gen/eyg/ast/pattern";
  // without type info
  //

  export let metadata;
  export let update_tree;

  function handleBeforeinput(event) {
    // console.log(event);
    // const { isComposing, inputType, data } = event;
    // if (isComposing === true) {
    //   // Deal with composition at the end to not annoy a user
    //   return;
    // } else if (inputType !== "insertText") {
    //   // Can't have multiline etc, where just using a keyboard kickoff.
    //   event.preventDefault();
    //   console.warn(inputType, "not supported for ???");
    // } else if (data === '"') {
    //   update_tree(metadata.path, Ast.binary(""));
    // } else if (data === "=") {
    //   event.preventDefault();
    //   console.log("assignment");
    // } else {
    //   event.preventDefault();
    //   // Though I think we will accept this for variables.
    //   console.warn(data, "not a command");
    // }
  }
  console.log(List.fromArray([]));
  let content;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element.focus();
    });
  }

  // scope should include equal
  function handleFocus() {}
  //   Need keydown for tab to work
  function handleKeydown(event) {
    if (event.key === "Tab") {
      if (content === "l") {
        event.preventDefault();
        let path = metadata.path;
        let newNode = Ast.let_(Pattern.variable(""), Ast.hole(), Ast.hole());
        update_tree(path, newNode);
        thenFocus(path);
      } else if (content.trim().replace(" ", "_")) {
        event.preventDefault();
        let label = content.trim().replace(" ", "_");
        let path = metadata.path;
        let newNode = Ast.variable(label);
        update_tree(path, newNode);
        thenFocus(path);
      }
    } else if (event.key === '"') {
      event.preventDefault();
      let path = metadata.path;
      let newNode = Ast.binary("");
      update_tree(path, newNode);
      thenFocus(path);
    } else if (event.key === "=") {
      event.preventDefault();
      let pattern = content.trim().replace(" ", "_");
      let path = metadata.path;
      let newNode = Ast.let_(Pattern.variable(pattern), Ast.hole(), Ast.hole());
      update_tree(path, newNode);
      thenFocus(Ast.append_path(path, 0));
    } else if (event.key === "[") {
      event.preventDefault();
      let path = metadata.path;
      let newNode = Ast.tuple_(List.fromArray([]));
      update_tree(path, newNode);
      thenFocus(Ast.append_path(path, 0));
    }
  }
  function handleBlur() {
    console.log("blue");
  }
</script>

<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  id={metadata.path ? "p" + metadata.path.toArray().join(",") : ""}
  contenteditable=""
  on:beforeinput={handleBeforeinput}
  bind:textContent={content}
  on:focus={handleFocus}
  on:keydown={handleKeydown}
  on:blur={handleBlur}
/>
<div>
  {#each metadata.scope.toArray() as [key]}
    <button
      class="hover:bg-gray-200 py-1 px-2 border rounded"
      on:click={() =>
        update_tree(metadata.path, Ast.variable(key)) &&
        thenFocus(metadata.path)}>{key}</button
    >
  {/each}
</div>

<!-- <span>{JSON.stringify(metadata.type_)}</span>
<span>{JSON.stringify(metadata.path.toArray())}</span> -->
<style>
  /* span:empty::before {
    content: "hole";
    color: white;
  } */
  span {
    display: inline-block;
    min-width: 1em;
  }
  /* span + div {
    display: none;
  } */
  span + div:focus-within {
    display: block;
  }
  span:focus + div {
    display: block;
  }
</style>
