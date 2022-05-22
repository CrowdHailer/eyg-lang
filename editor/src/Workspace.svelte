<script>
  import Editor from "./components/Editor.svelte";
  import Mount from "./workspace/Mount.svelte";

  import * as UI from "../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/ui";
  import * as Gleam from "../../eyg/build/dev/javascript/eyg/dist/gleam";

  import { tick } from "svelte";

  let workspace;
  let state;
  function update(transform) {
    let [next, tasks] = transform(state);
    tasks.forEach((task) => {
      task.then(update);
    });
    let changed = !Gleam.isEqual(next, state);
    state = next;
    tick().then(() => {
      if (changed) {
        let element = document.querySelector("input");
        if (element) {
          element.focus();
          element.select();
        } else {
          workspace && workspace.focus();
        }
      }
    });
    return changed;
  }

  update(UI.init);

  function handleKeydown(event) {
    //   only after keypress/up do we have a value, but space and enter come after
    let text = event.target.closest("input")?.value || "";
    let transform = UI.keydown(event.key, event.ctrlKey, text);
    let changed = update(transform);
    if (changed) event.preventDefault();
  }

  function getMarker(element) {
    let markers = [];
    element = element.closest("[data-ui]");
    while (element) {
      markers.unshift(element.dataset.ui);
      element = element.parentElement?.closest("[data-ui]");
    }
    return Gleam.toList(markers);
  }

  function handleClick(event) {
    let transform = UI.click(getMarker(event.target));
    if (update(transform)) event.preventDefault();
  }
</script>

<div
  class="flex min-h-screen outline-none"
  tabindex="-1"
  bind:this={workspace}
  autofocus
  on:click={handleClick}
  on:keypress={handleKeydown}
>
  <div
    class="w-1/2 max-h-screen flex-1 overflow-x-hidden border-2 border-gray-200 flex flex-col"
    class:border-blue-200={UI.editor_focused(state)}
    data-ui="editor"
  >
    {#if UI.get_editor(state)}
      <!-- Leave editor as AST manipulator -->
      <Editor editor={UI.get_editor(state)} />
    {/if}
  </div>
  <div
    class="w-1/2 max-h-screen flex-1 overflow-x-hidden border-2 border-gray-200"
    class:border-blue-200={UI.bench_focused(state)}
    data-ui="bench"
  >
    {#each UI.benches(state) as app, index}
      <Mount key={app.key} mount={app.mount} {index} />
    {/each}
  </div>
</div>
