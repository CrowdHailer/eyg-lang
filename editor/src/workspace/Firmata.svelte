<script context="module">
  console.log("Starting Firmata module");
  import { connectDevice } from "../device_connection";
  // Module context to be global without being part of workspace
  // Probably can have an Actor tree under workspace in the future

  let setScan = function () {};
  //   Should this be outside module context?
  async function handleConnect(event) {
    // event.cancelBubble();
    console.log(event);
    setScan = await connectDevice();
  }
</script>

<!-- Global connect_device to keep thing moving or not -->
<script>
  //   import * as Gleam from "../../../eyg/build/dev/javascript/eyg/dist/gleam";
  import * as Option from "../../../eyg/build/dev/javascript/gleam_stdlib/dist/gleam/option.mjs";

  // Nil or ready
  export let scan;
  $: (function () {
    if (scan instanceof Option.Some) {
      setScan(scan[0]);
    } else {
    }
  })();
</script>

<div class="p-6">
  <h1>Firmata</h1>
  <button
    class="m-1 p-1 bg-blue-100 rounded border border-black"
    on:click={handleConnect}>Connect</button
  >
</div>
