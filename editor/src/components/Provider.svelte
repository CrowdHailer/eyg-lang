<script>
  export let generator;
  export let metadata;
  export let update_tree;
  import * as Ast from "../gen/eyg/ast";

  function activate(event) {
    const { isComposing, inputType, data } = event;
    if (isComposing === true) {
      // Deal with composition at the end to not annoy a user
      return;
    } else if (inputType !== "insertText") {
      // Can't have multiline etc, where just using a keyboard kickoff.
      event.preventDefault();
      console.warn(inputType, "not supported for ???");
    } else if (data === '"') {
      update_tree(metadata.path, Ast.binary(""));
    } else if (data === "=") {
      event.preventDefault();
      console.log("assignment");
    } else {
      event.preventDefault();
      // Though I think we will accept this for variables.
      console.warn(data, "not a command");
    }
  }
  let string;

  let span;
  $: window.span = span;
</script>

<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  contenteditable=""
  on:beforeinput={activate}
  bind:innerHTML={string}
  bind:this={span}
/>
<span>{JSON.stringify(metadata.type_)}</span>
<span>{JSON.stringify(metadata.path.toArray())}</span>

<style>
  /* span:empty::before {
    content: "hole";
    color: white;
  } */
  span {
    display: inline-block;
    min-width: 1em;
  }
</style>
