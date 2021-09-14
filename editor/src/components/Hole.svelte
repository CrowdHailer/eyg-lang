<script>
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
  import ErrorNotice from "./ErrorNotice.svelte";

  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import * as Edit from "../gen/eyg/ast/edit";
  import * as Option from "../gen/gleam/option";

  export let metadata;
  export let global;
  export let required = false;

  let content;
  function handleKeydown(event) {
    const { key, ctrlKey } = event;
    let action = Edit.shotcut_for_blank(content, key, ctrlKey);
    Option.map(action, (action) => {
      let edit = Edit.edit(action, metadata.path);
      event.preventDefault();
      event.stopPropagation();
      dispatch("edit", edit);
    });
    event.stopPropagation();
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

  let variables = [];
  $: variables = metadata.scope
    .toArray()
    .filter(([k]) => content && k.startsWith(content))
    .filter(([k]) => k !== "" && k !== "$");
</script>

<span
  class:required
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  id={Ast.path_to_id(metadata.path)}
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
  class:hidden={!active || !variables.length}
  class="my-1 py-1 bg-yellow-50"
  bind:this={helpBox}
>
  <span>variables: </span>
  {#each variables as [key]}
    <button
      class="hover:bg-gray-200 px-1 outline-none focus:border-gray-500 border-b-2 border-gray-100"
      on:click={() =>
        dispatch("edit", Edit.replace_with_variable_action(key, metadata.path))}
      on:focus={focusHelp}
      on:blur={tryBlur}>{key}</button
    >
  {/each}
</div>
<ErrorNotice type_={metadata.type_} />

<style>
  span.required {
    display: inline-block;
    min-width: 1em;
  }
  span:not(.required):not(:first-child):focus::before {
    min-width: 1em;

    content: ", ";
  }
</style>
