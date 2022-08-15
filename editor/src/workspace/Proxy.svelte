<script>
  import * as Proxy from "../../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/proxy";
  import { Ok, Error } from "../../../eyg/build/dev/javascript/eyg/dist/gleam";

  export let state;
  let message = "";
  let p;
  $: console.log(new Ok(), state, state instanceof Ok);
  $: (() => {
    if (state instanceof Ok) {
      console.log("proxy");
      // Proxy.run(state["0"]);
      p = state["0"];
      message = "";
    } else {
      p = undefined;
      message = state["0"];
    }
  })();
  // Possible could just pass in state
  (async function () {
    while (true) {
      // Need async in JS land for while loop and to make sure svelte updating of source is patched into while loop
      let r = await Proxy.fetch_request();
      console.log(r);
      Proxy.handle(r, p);
    }
  })();
</script>

<h1>Hello proxy</h1>
{message}
