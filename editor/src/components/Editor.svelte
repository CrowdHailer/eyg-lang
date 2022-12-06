<script>
  import * as Display from "../../../eyg/build/dev/javascript/eyg/eyg/editor/display";
  import Expression from "./Expression.svelte";

  import * as Editor from "../../../eyg/build/dev/javascript/eyg/eyg/editor/editor";
  import * as UI from "../../../eyg/build/dev/javascript/eyg/eyg/editor/ui";

  // import { Octokit } from "https://cdn.skypack.dev/@octokit/rest";
  // Use let in components const causes nil obkject issues
  let ghAccessToken = "ghAccessToken";
  let octokit = new window.Octokit({
    auth: localStorage.getItem(ghAccessToken),
  });
  window.setAccessToken = function (token) {
    localStorage.setItem(ghAccessToken, token);
  };
  export let editor;
  $: window.eyg_source = Editor.dump(editor);

  let saving = false;
  async function save() {
    if (saving) {
      return;
    }
    saving = true;

    const owner = "midas-framework";
    const repo = "project_wisdom";
    const path = "editor/public/saved.json";
    const { data } = await octokit.rest.repos.getContent({ owner, repo, path });
    const sha = data.sha;
    const message = "saveed from editor";
    const content = btoa(Editor.dump(editor));
    await octokit.rest.repos.createOrUpdateFileContents({
      owner,
      repo,
      path,
      message,
      content,
      sha,
    });
    saving = false;
  }
  // This can definetly become something we do in gleam
  let deploying = false;
  const host = window.location.host;
  const local = host.startsWith("localhost:");
  console.log("local", local);
  const deployOrigin = local
    ? "http://localhost:5002"
    : "https://cluster.web.petersaxton.uk";
  async function deploy() {
    if (deploying) {
      return;
    }
    deploying = true;
    // TODO put in scret
    const url = deployOrigin + "/deploy";
    const response = await fetch(url, {
      method: "POST",
      body: Editor.dump(editor),
    });
    console.log(response);
    deploying = false;
  }
</script>

<button class="m-1 p-1 bg-blue-100 rounded border border-black" on:click={save}
  >{#if saving}
    Saving
  {:else}
    Save
  {/if}</button
>
<button
  class="m-1 p-1 bg-blue-100 rounded border border-black"
  on:click={deploy}
  >{#if deploying}
    Deploying
  {:else}
    Deploy
  {/if}</button
>
{#if editor.show == "code"}
  <pre class="w-full m-auto px-10 py-4" tabindex="0">{editor.cache.code}</pre>
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

      <div class="sticky bottom-0 bg-white py-2">
        {#if UI.is_composing(editor)}
          <input
            class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
            id="draft"
            type="text"
            value={editor.mode.content || editor.mode.filter || ""}
          />
          <nav>
            {#each UI.choices(editor) as choice, i}
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
    class:bg-red-200={Display.target_type(editor)[0]}
  >
    type: {Display.target_type(editor)[1]}
  </div>
{/if}
