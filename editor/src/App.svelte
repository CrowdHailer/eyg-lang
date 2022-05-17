<script>
    import Editor from "./components/Editor.svelte";
    import Spreadsheet from "./spreadsheet/Spreadsheet.svelte";

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
        <Editor {source} />
    {/if}
{/await}
