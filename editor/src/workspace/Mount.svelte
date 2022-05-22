<script>
  import * as Mount from "../../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/workspace";

  import Static from "./Static.svelte";
  import TestSuite from "./TestSuite.svelte";
  import UI from "./UI.svelte";
  import String2String from "./String2String.svelte";

  export let index;
  export let key;
  export let mount;
  export let active;
</script>

<!-- TODO collapse and show at this level -->
<div class="p-6" data-ui="mount:{index}">
  <span>{key}</span>
  {#if mount instanceof Mount.Static}
    <Static value={mount.value} />
  {:else if mount instanceof Mount.TestSuite}
    <TestSuite result={mount.result} />
  {:else if mount instanceof Mount.UI}
    <UI />
  {:else if mount instanceof Mount.String2String}
    <String2String output={mount.output} {active} />
  {:else}
    {JSON.stringify(mount)}
  {/if}
</div>
