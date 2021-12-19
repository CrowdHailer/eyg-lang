<script>
    import * as Display from "../gen/eyg/editor/display";

    export let metadata;
    export let value;
</script>

<span
    class="text-green-800 border-2 border-transparent outline-none rounded inline-block"
    class:border-red-500={metadata.errored && !Display.is_target(metadata)}
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}>{value}</span
>
