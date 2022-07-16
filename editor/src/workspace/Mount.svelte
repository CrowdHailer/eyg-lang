<script>
  import * as Mount from "../../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/workspace";

  import Static from "./Static.svelte";
  import TestSuite from "./TestSuite.svelte";
  import UI from "./UI.svelte";
  import String2String from "./String2String.svelte";
  import Firmata from "./Firmata.svelte";
  import Server from "./Server.svelte";

  export let index;
  export let key;
  export let mount;
  export let active;
</script>

<!-- TODO collapse and show at this level -->
<div class="h-full">
  {#if mount instanceof Mount.Static}
    <!-- TODO Put this in active footer next to details -->
    <p><strong>{key}:</strong> Static</p>
    <Static value={mount.value} />
  {:else if mount instanceof Mount.TestSuite}
    <p><strong>{key}:</strong> Test Suite</p>
    <TestSuite result={mount.result} />
  {:else if mount instanceof Mount.UI}
    <p><strong>{key}:</strong> UI</p>
    <UI rendered={mount.rendered} />
  {:else if mount instanceof Mount.String2String}
    <p><strong>{key}:</strong> CLI</p>
    <String2String input={mount.input} output={mount.output} {active} />
  {:else if mount instanceof Mount.Firmata}
    <p><strong>{key}:</strong> Firmata</p>
    <Firmata scan={mount.scan} />
  {:else if mount instanceof Mount.Server}
    <p><strong>{key}:</strong> Server</p>
    <Server handle={mount.handle} />
  {:else}
    {JSON.stringify(mount)}
  {/if}
</div>
