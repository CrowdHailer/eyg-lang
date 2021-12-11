<script>
  import { tick } from "svelte";

  import Expression from "./components/Expression.svelte";
  import * as Editor from "./gen/eyg/ast/editor";
  let editor = Editor.init(`{"node": "Hole"}`);
  (async function () {
    let response = await fetch("/saved.json");
    let text = await response.text();
    editor = Editor.init(text);
  })();

  function eventToTarget(event) {
    let element = event.target;
    return element.closest("[data-editor]").dataset.editor;
  }

  let code = "";
  let dump = "";
  let downloadBlob = new Blob([], { type: "application/json" });
  function updateFocus(editor) {
    tick().then(() => {
      if (Editor.is_draft(editor)) {
        document.getElementById("draft").focus();
      } else if (Editor.is_select(editor)) {
        document.getElementById("filter").focus();
      } else if (Editor.is_command(editor)) {
        document.querySelector("[data-editor='root']").focus();
        // Only eval once back to the command mode, this is probably right but also need to make sure to add holes to warnings.
        try {
          let rendered = Editor.codegen(editor);
          // with eval {} is considered a block of code, not an object
          if (rendered[0]) {
            code = rendered[1];
            console.log(Editor.eval$(editor));
          }
        } catch (error) {
          console.error("Caught", error);
        }
        try {
          dump = Editor.dump(editor);
          downloadBlob = new Blob([dump], { type: "application/json" });
        } catch (error) {
          console.error("Caught", error);
        }
      }
    });
  }

  function handleClick(event) {
    try {
      editor = Editor.handle_click(editor, eventToTarget(event));
      updateFocus(editor);
    } catch (error) {
      console.error("Caught", error);
    }
  }

  function handleKeydown(event) {
    let tmp;
    try {
      if (event.metaKey) {
        return true;
      }

      event.preventDefault();
      tmp = Editor.handle_keydown(editor, event.key, event.ctrlKey);
    } catch (error) {
      return console.error("Caught", error);
    }
    editor = tmp;
    updateFocus(editor);
  }

  function handleDraftKeydown(event) {
    try {
      if (event.metaKey) {
        return true;
      }
      if (event.key == "Escape" || event.key == "Tab") {
        event.preventDefault();
        editor = Editor.handle_change(editor, event.target.value);
        updateFocus(editor);
      }
      event.stopPropagation();
    } catch (error) {
      console.error("Caught", error);
    }
  }

  function handleSelectKeydown(event) {
    try {
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
    } catch (error) {
      console.error("Caught", error);
    }
  }

  function handleChange(event) {
    try {
      editor = Editor.handle_change(editor, event.target.value);
      updateFocus(editor);
    } catch (error) {
      console.error("Caught", error);
    }
  }
  const HOME = "HOME";
  const DUMP = "DUMP";
  const CODE = "CODE";
  let page = HOME;
  updateFocus(editor);
</script>

<!-- {JSON.stringify(editor.selection)} -->
<div class="max-w-4xl w-full m-auto px-10 py-4">
  <nav class="flex py-2">
    <button
      class="text-gray-600 hover:underline"
      class:underline={page == HOME}
      on:click={() => (page = HOME)}>Home</button
    >
    <button
      class="ml-auto pl-2 text-gray-600 hover:underline"
      class:underline={page == CODE}
      on:click={() => (page = page == CODE ? HOME : CODE)}>Code</button
    >
    <button
      class="pl-2 text-gray-600 hover:underline"
      class:underline={page == DUMP}
      on:click={() => (page = page == DUMP ? HOME : DUMP)}>Dump</button
    >
  </nav>
  <!-- Make it so you can inspect saved code in case of crash -->
  <div class:hidden={page != DUMP}>
    <a
      class="p-2 w-full bg-gray-200 inline-block text-center hover:bg-gray-400"
      download="eyg.json"
      href={URL.createObjectURL(downloadBlob)}>Download</a
    >
    <textarea class="w-full" rows="40">{dump}</textarea>
  </div>
  {#if page == CODE}
    <pre>
      <!-- Doesn't work for single line programs they are not rendered multiline -->
    {#if code}
        {code}
      {/if}
  </pre>
  {:else if page == HOME}
    <div
      class="outline-none"
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
  {/if}
</div>
<aside class="absolute top-0 right-0 p-2 border-l-4 border-red-700 bg-white">
  {#each editor.typer.inconsistencies.toArray() as reason}
    <p>{reason}</p>
  {/each}
</aside>
