<script>
  import * as Mount from "../../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/workspace";

  import TestSuite from "./TestSuite.svelte";
  import UI from "./UI.svelte";
  import String2String from "./String2String.svelte";
  import Firmata from "./Firmata.svelte";
  import Server from "./Server.svelte";
  import Pure from "./Pure.svelte";
  import Interpreted from "./Interpreted.svelte";
  import Proxy from "./Proxy.svelte";

  export let key;
  export let mount;
  export let active;
</script>

<div class="h-full">
  {#if mount instanceof Mount.TestSuite}
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
  {:else if mount instanceof Mount.Universal}
    <p><strong>{key}:</strong> Universal</p>
    <Server handle={mount.handle} />
  {:else if mount instanceof Mount.IServer}
    <p><strong>{key}:</strong> IServer</p>
    <Server handle={mount.handle} />
  {:else if mount instanceof Mount.Pure}
    <p><strong>{key}:</strong> Pure</p>
    <Pure state={mount[0]} />
  {:else if mount instanceof Mount.Interpreted}
    <p><strong>{key}:</strong> Interpreted</p>
    <Interpreted source={mount.source} />
  {:else if mount instanceof Mount.Proxy}
    <p><strong>{key}:</strong> Proxy</p>
    <Proxy state={mount.state} />
  {:else}
    {JSON.stringify(mount)}
  {/if}
</div>
