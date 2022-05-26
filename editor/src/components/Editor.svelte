<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/display";
  import Expression from "./Expression.svelte";

  import * as Editor from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/editor";
  import * as UI from "../../../eyg/build/dev/javascript/eyg/dist/eyg/editor/ui";

  // TODO connect firmata
  export let editor;
</script>

{#if editor.show == "code"}
  <pre class="w-full m-auto px-10 py-4" tabindex="0">{Editor.codegen(
      editor
    )[1]}</pre>
  <div class="sticky bottom-0 bg-gray-200 p-2 pb-4" />
{:else if editor.show == "dump"}
  <textarea class="w-full h-full m-auto p-4" tabindex="0"
    >{Editor.dump(editor)}</textarea
  >
  <a
    class="sticky bottom-0 bg-gray-200 p-2 pb-4"
    download="eyg.json"
    href={URL.createObjectURL(
      new window.Blob([Editor.dump(editor)], { type: "application/json" })
    )}
  >
    Download
  </a>
{:else}
  <div class="w-full m-auto px-10 py-4">
    <div class="outline-none" tabindex="-1" data-ui="root">
      <Expression expression={Display.display(editor)} />

      <!-- TODO unify content and choices BUT maybe we don't need that because we will switch to update variable/ type hole filtering -->
      <div class="sticky bottom-0 bg-white py-2">
        {#if UI.is_composing(editor)}
          <input
            class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
            id="draft"
            type="text"
            value={editor.mode.content || ""}
          />
          <!-- TODO remove all toArrays -->
          <nav>
            {#each editor.mode?.choices?.toArray() || [] as choice, i}
              <button
                class="m-1 p-1 bg-blue-100 rounded border-black"
                class:border={i == 0}
                data-ui={choice}>{choice}</button
              >
            {/each}
          </nav>
        {/if}
      </div>
    </div>
  </div>
  <div
    class="sticky bottom-0 bg-gray-200 p-2 pb-4"
    class:bg-red-200={Editor.target_type(editor)[0]}
  >
    type: {Editor.target_type(editor)[1]}
  </div>
{/if}
