<script>
  import { log } from "../../../eyg/build/dev/javascript/gleam_stdlib/dist/gleam_stdlib.mjs";
  import * as Option from "../../../eyg/build/dev/javascript/gleam_stdlib/dist/gleam/option.mjs";

  export let handle;
  let handlerFn;
  let exchanges = [];
  // TODO delete old spotless
  // TODO make dynamic
  const clientId = "123456";
  const api = "http://localhost:8080";
  async function pullRequests() {
    while (true) {
      let fetched = await fetch(api + "/request/" + clientId);
      if (fetched.status === 200) {
        let data = await fetched.json();
        console.log(data);
        // let mod = await getModule();
        data.path = data.path.slice(7) || "/";
        let status = 200;
        let body = "";
        if (handlerFn) {
          body = handlerFn(data.method, data.path, data.body);
          console.log("in herer", body, handlerFn);
        }
        exchanges = exchanges.concat(exchanges, [
          { request: data, response: { status, body } },
        ]);
        // logRequest(data, { status, body });
        // console.log(body);
        fetch(api + "/response/" + data.response_id, {
          method: "POST",
          body: JSON.stringify({ status, body }),
        });
      }
    }
  }
  pullRequests();

  $: (function () {
    if (handle instanceof Option.Some) {
      handlerFn = handle[0];
    } else {
      handlerFn = undefined;
    }
  })();
</script>

{#if handlerFn}
  <p class="p-2 bg-green-200">
    Ready - <a href="http://localhost:8080/{clientId}"
      >http://localhost:8080/{clientId}</a
    >
  </p>
{:else}
  <p class="p-2 bg-red-200">Not Ready</p>
{/if}

<div>
  <h2 class="">Requests handled</h2>
  {#each exchanges as e}
    <div class="px-2 flex">
      <span class="flex-1">{e.request.method} {e.request.path}</span>
      <span class="flex-1">
        {e.response.status}
        {#if e.response.body.length > 30}{e.response.body.length} bytes{:else}{e
            .response.body}{/if}</span
      >
    </div>
  {:else}
    <div id="request-log" class="px-2 text-gray-600">No requests</div>
  {/each}
</div>
