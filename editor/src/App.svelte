<script>
  import { tick } from "svelte";

  import Expression from "./components/Expression.svelte";
  import * as Editor from "./gen/eyg/ast/editor";
  let editor = Editor.init()

  function eventToTarget(event) {
    let element = event.target
    return element
    .closest("[data-editor]")
    .dataset.editor
  }

  function updateFocus(editor) {
    tick().then(() => {
      console.log("then");
      if (Editor.is_draft(editor)) {
        console.log("focus");
        document.getElementById("draft").focus()
      } else {
        // TODO stringify in the gleam code
        let pString = "p:" + editor.position.toArray().join(",");

        let after = document.querySelector("[data-editor='" + pString + "']");
        if (after) {
          after.focus();
        } else {
          console.error("Action had no effect, was not able to focus cursor")
        }
      }
    });
  }

  function handleClick(event) {
    console.log("click");

    editor = Editor.handle_click(editor, eventToTarget(event))
    updateFocus(editor)
  }

    function handleKeydown(event) {
    if (event.metaKey) {
      return true
    }

    event.preventDefault()
    editor = Editor.handle_keydown(editor, event.key, event.ctrlKey);
    updateFocus(editor)
  }

  function handleChange(event) {
    console.log("change");
    editor = Editor.handle_change(editor, event.target.value)
    updateFocus(editor)
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white relative"
  on:click={handleClick}
  on:keydown={handleKeydown}
>
  <Expression
    expression={editor.tree}
    position={[]}
  />
  <div class="sticky bottom-0 bg-white py-2">
    {#if Editor.is_command(editor)}
    <p>type: {Editor.target_type(editor)}</p>
    {:else if Editor.is_draft(editor)}
    <input
      class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
      id="draft"
      type="text"
      value={editor.mode.content}
      on:click={(e) => e.stopPropagation()}
      on:keydown={(e) => e.stopPropagation()}
      on:change={handleChange}
      >
    {:else if Editor.is_select(editor)}
      <nav>variables:
        {#each Editor.in_scope(editor).toArray() as v}
          <button data-editor="v:{v}" class="m-1 p-1 bg-blue-100 rounded">{v}</button>
        {/each}
      </nav>
    {/if}
  </div>
</div>
<!-- <pre class="max-w-4xl mx-auto my-2 bg-gray-100 p-1">
  {generated}
</pre> -->
