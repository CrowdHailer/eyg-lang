<script>
  import * as Proxy from "../../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/proxy";
  import { Ok, Error } from "../../../eyg/build/dev/javascript/eyg/dist/gleam";

  export let state;
  let message = "";
  let program;
  $: (() => {
    if (state instanceof Ok) {
      program = state["0"];
      message = "";
    } else {
      program = undefined;
      message = state["0"];
    }
  })();
  // Possible could just pass in state
  const poll = async function () {
    // TODO proxy needs to shut down for errors
    while (false) {
      // Need async in JS land for while loop and to make sure svelte updating of source is patched into while loop
      let r = await Proxy.fetch_request();
      if (program) {
        Proxy.handle(r, state);
      }
    }
  };
  if (window.location.hostname.startsWith("localhost")) {
    poll();
  }
</script>

<h1>Hello proxy</h1>
{message}
