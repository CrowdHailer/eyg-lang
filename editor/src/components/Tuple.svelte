<script>
  import { tick } from "svelte";

  import TermInput from "./TermInput.svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import * as ListUtils from "../gen/gleam/list";
  import { List } from "../gen/gleam";
  export let metadata;
  export let elements;
  export let update_tree;

  // function handleNewElement({detail: {content: }}) {
  //   console.log(params);
  // }
  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element.focus();
    });
  }

  let newContent = "";
  function handleKeydown(event) {
    if (event.key === "Tab") {
      if (newContent === "l") {
        event.preventDefault();
        let path = metadata.path;
        let newNode = Ast.let_(Pattern.variable(""), Ast.hole(), Ast.hole());
        update_tree(path, newNode);
        thenFocus(path);
      } else {
      }
    } else if (event.key === '"') {
      event.preventDefault();
      let path = metadata.path;
      let newElement = Ast.binary("");
      let e = ListUtils.append(elements, List.fromArray([newElement]));
      let newNode = Ast.tuple_(e);
      update_tree(path, newNode);
      thenFocus(Ast.append_path(path, elements.toArray().length + 1));
    } else if (event.key === "=") {
      let pattern = newContent.trim().replace(" ", "_");
      event.preventDefault();
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
</script>

[{#each elements.toArray() as element, i}
  <Expression
    expression={element}
    {update_tree}
    on:pinpoint
    on:depoint
  />,&nbsp;
{/each}
<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  id={metadata.path
    ? "p" +
      Ast.append_path(metadata.path, elements.toArray().length)
        .toArray()
        .join(",")
    : ""}
  contenteditable=""
  bind:textContent={newContent}
  on:keydown={handleKeydown}
/>
]
