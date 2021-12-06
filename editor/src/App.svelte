<script>
  import { tick } from "svelte";

  import Expression from "./components/Expression.svelte";
  import * as Editor from "./gen/eyg/ast/editor";
  let editor = Editor.init();

  function eventToTarget(event) {
    let element = event.target;
    return element.closest("[data-editor]").dataset.editor;
  }

  function updateFocus(editor) {
    tick().then(() => {
      if (Editor.is_draft(editor)) {
        document.getElementById("draft").focus();
      } else if (Editor.is_select(editor)) {
        document.getElementById("filter").focus();
      } else if (Editor.is_command(editor)) {
        document.querySelector("[data-editor='root']").focus();
      }
    });
  }

  function handleClick(event) {
    editor = Editor.handle_click(editor, eventToTarget(event));
    updateFocus(editor);
  }

  function handleKeydown(event) {
    if (event.metaKey) {
      return true;
    }

    event.preventDefault();
    editor = Editor.handle_keydown(editor, event.key, event.ctrlKey);
    updateFocus(editor);
  }

  function handleDraftKeydown(event) {
    if (event.metaKey) {
      return true;
    }
    if (event.key == "Escape" || event.key == "Tab") {
      event.preventDefault();
      editor = Editor.handle_change(editor, event.target.value);
      updateFocus(editor);
    }
    event.stopPropagation();
  }

  function handleSelectKeydown(event) {
    if (event.metaKey || event.key == "Escape") {
      return true;
    }
    if (event.key == "Enter" || event.key == " ") {
      let variable = Editor.in_scope(editor).toArray()[0];
      if (variable) {
        editor = Editor.handle_click(editor, "v:" + variable);
      }
      updateFocus(editor);
      event.preventDefault();
    }
    event.stopPropagation();
  }

  function handleChange(event) {
    editor = Editor.handle_change(editor, event.target.value);
    updateFocus(editor);
  }
</script>

<header class="max-w-4xl mx-auto pb-2 pt-6">
  <h1 class="text-2xl">Editor</h1>
</header>
<div
  class="max-w-4xl mx-auto rounded shadow px-10 py-6 bg-white relative outline-none"
  tabindex="-1"
  data-editor="root"
  on:click={handleClick}
  on:keydown={handleKeydown}
>
  <Expression expression={Editor.display(editor)} />
  <div class="sticky bottom-0 bg-white py-2">
    {#if Editor.is_command(editor)}
      {#if Editor.target_type(editor)[0]}
        <p class="bg-red-500 rounded p-1 text-white">
          {Editor.target_type(editor)[1]}
        </p>
      {:else}
        <p>type: {Editor.target_type(editor)[1]}</p>
      {/if}
    {:else if Editor.is_draft(editor)}
      <input
        class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
        id="draft"
        type="text"
        value={editor.mode.content}
        on:click={(e) => e.stopPropagation()}
        on:keydown={handleDraftKeydown}
        on:change={handleChange}
      />
    {:else if Editor.is_select(editor)}
      <div on:keydown={handleSelectKeydown}>
        <input
          class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
          id="filter"
          on:click={(e) => e.stopPropagation()}
          type="text"
          bind:value={editor.mode.filter}
        />
        <nav>
          variables:
          {#each Editor.in_scope(editor).toArray() as v, i}
            <button
              class="m-1 p-1 bg-blue-100 rounded border-black"
              class:border={i == 0}
              data-editor="v:{v}">{v}</button
            >
          {/each}
        </nav>
      </div>
    {/if}
  </div>
</div>
<!-- <pre class="max-w-4xl mx-auto my-2 bg-gray-100 p-1">
  {generated}
</pre> -->
