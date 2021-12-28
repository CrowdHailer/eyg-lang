<script>
    import Workspace from "./components/Workspace.svelte";

    let source = (async function () {
        // Do this with an async component
        let response = await fetch("/saved.json");
        return await response.text();
    })();
</script>

{#await source}
    Loading
{:then source}
    <Workspace {source} />
{/await}
