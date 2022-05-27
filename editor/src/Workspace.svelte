<script>
  import Editor from "./components/Editor.svelte";
  import Mount from "./workspace/Mount.svelte";

  import * as UI from "../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/ui";
  import * as Gleam from "../../eyg/build/dev/javascript/eyg/dist/gleam";
  import * as Option from "../../eyg/build/dev/javascript/gleam_stdlib/dist/gleam/option.mjs";

  import { tick } from "svelte";

  let workspace;
  let state;
  function update(transform, skip) {
    let [next, tasks] = transform(state);
    tasks.forEach((task) => {
      task.then(update);
    });
    let changed = !Gleam.isEqual(next, state);
    state = next;
    tick().then(() => {
      if (changed && !skip) {
        let element = document.querySelector("input:not([disabled]");
        if (element) {
          element.focus();
          // TODO move to a should highlight field in editor
          state.editor[0].mode.content ? element.select() : null;
        } else {
          workspace && workspace.focus();
        }
      }
    });
    return changed;
  }

  update(UI.init);

  function handleKeydown(event) {
    // TODO   only after keypress/up do we have a value, but space and enter come after
    if (event.target.closest('[data-ui="bench"]')) {
      return;
    }
    let inputEl = event.target.closest("input");
    let input = inputEl ? new Option.Some(inputEl.value) : new Option.None();
    // TODO this change is forcing focus on the elements Need to update to a do the select thing
    // Also it would probably be good to just not handle key down if in an input. BUT we want to capture enter escape keys
    let transform = UI.keydown(event.key, event.ctrlKey, input);
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

  function handleInput(event) {
    let data = event.target.value;
    let marker = getMarker(event.target);
    let transform = UI.on_input(data, marker);
    update(transform, true);
    // console.log(data, marker);
    // preventDefault does nothing here.
    // event.preventDefault();
  }
  let app;
  $: app = UI.running_app(state);
</script>

<div
  class="flex min-h-screen outline-none"
  tabindex="-1"
  bind:this={workspace}
  autofocus
  on:click={handleClick}
  on:keypress={handleKeydown}
  on:input={handleInput}
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
    class="w-1/2 max-h-screen flex-1 overflow-x-hidden border-2 border-gray-200 flex flex-col"
    class:border-blue-200={UI.bench_focused(state)}
    data-ui="bench"
  >
    <!-- TODO Mount active outside individual mount -->
    {#if app}
      <Mount key={app.key} mount={app.mount} active={UI.bench_focused(state)} />
    {/if}
    <div class="sticky bottom-0 bg-gray-200 p-2 pb-4 text-right">
      <details>
        <summary class="cursor-pointer">Apps</summary>
        <ul>
          {#each UI.benches(state) as app, index}
            <li data-ui="mount:{index}">{app.key}</li>
          {/each}
        </ul>
      </details>
    </div>
  </div>
</div>
