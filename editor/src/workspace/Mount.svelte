<script>
  import * as Mount from "../../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/workspace";

  import Static from "./Static.svelte";
  import TestSuite from "./TestSuite.svelte";
  import UI from "./UI.svelte";

  export let mount;
</script>

{#if mount instanceof Mount.Static}
  <Static value={mount.value} />
{:else if mount instanceof Mount.TestSuite}
  <TestSuite result={mount.result} />
{:else if mount instanceof Mount.UI}
  <UI />
{:else}
  {JSON.stringify(mount)}
{/if}
