<script>
    import Workspace from "./components/Workspace.svelte";
    import Spreadsheet from "./spreadsheet/Workspace.svelte";

    let source = (async function () {
        let response = await fetch("/saved.json");
        return await response.text();
    })();
</script>

{#await source}
    Loading
{:then source}
    {#if window.location.hash.slice(1) == "spreadsheet"}
        <Spreadsheet {source} />
    {:else}
        <Workspace {source} />
    {/if}
{/await}
