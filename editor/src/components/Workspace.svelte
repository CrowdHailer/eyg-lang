<script>
  import { tick } from "svelte";
  import * as Display from "../gen/eyg/editor/display";

  import Expression from "./Expression.svelte";
  import Select from "./Select.svelte";

  import * as Editor from "../gen/eyg/ast/editor";
  import * as Platform from "../gen/platform/browser";
  import * as Eyg from "../gen/eyg";
  import * as Ast from "../gen/eyg/ast";
  import * as Gleam from "../gen/gleam";

  export let source;

  window.compile = Eyg.compile;
  let editor = Editor.init(source, Platform.harness());

  function eventToTarget(event) {
    let element = event.target;
    return element.closest("[data-editor]").dataset.editor;
  }

  let code = "";
  let dump = "";
  let value = "";
  let downloadBlob = new Blob([], { type: "application/json" });

  let testGood = true;
  // Gleam inspect makes pretty but is not the runtime representation
  // JSON .stringfy just hides/ignores functions
  function updateFocus(editor) {
    tick().then(() => {
      if (Editor.is_draft(editor)) {
        let element = document.getElementById("draft");
        element.focus();
        element.select();
      } else if (Editor.is_select(editor)) {
        document.getElementById("filter").focus();
      } else if (Editor.is_command(editor)) {
        document.querySelector("[data-editor='root']").focus();
        // Only eval once back to the command mode, this is probably right but also need to make sure to add holes to warnings.
        try {
          // TODO pass in native here
          let rendered = Editor.codegen(editor);
          window.tree = editor.tree;
          // with eval {} is considered a block of code, not an object
          if (rendered[0]) {
            code = rendered[1];
            let returned = Editor.eval$(editor);
            window.returned = returned;
            testGood = returned.test == "True";
            value = JSON.stringify(returned);
          } else {
            value = "";
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
      if (event.key == "Tab") {
        event.preventDefault();
        editor = Editor.handle_change(editor, event.target.value);
        updateFocus(editor);
      } else if (event.key == "Escape") {
        event.preventDefault();
        editor = Editor.cancel_change(editor);
        updateFocus(editor);
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

  function makeSelection(value) {
    try {
      editor = Editor.handle_change(editor, value);
      updateFocus(editor);
    } catch (error) {
      console.error("Caught", error);
    }
  }
</script>

<div class="max-w-4xl w-full m-auto px-10 py-4">
  <nav class="flex py-2">
    <button
      class="text-gray-600 hover:underline"
      class:underline={page == HOME}
      on:click={() => (page = HOME)}>Home</button
    >
    <span
      class="ml-auto w-36"
      class:bg-green-500={testGood}
      class:bg-red-500={!testGood}
    />
    <button
      class="pl-2 text-gray-600 hover:underline"
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
      <Expression expression={Display.display(editor)} />
      <p class="bg-gray-200 p-1">
        <span>Output = </span><span>{value}</span>
      </p>
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
          <Select choices={editor.mode.choices} {makeSelection} />{/if}
      </div>
    </div>
  {/if}
</div>
<aside
  class="absolute top-0 right-0 bg-white w-full max-w-sm "
  on:click={handleClick}
>
  {#each Editor.inconsistencies(editor).toArray() as [path, reason]}
    <p
      class="px-2 border-l-4 border-red-700 text-gray-600 hover:text-black cursor-pointer"
      class:border-l-8={Editor.is_selected(editor, path)}
      data-editor={Display.position_to_marker(path)}
    >
      {reason}
    </p>
  {/each}
</aside>
