<script>
  import Indent from "./Indent.svelte";
  export let value;
  export let update_tree;
  export let path;
  export let count;
  let string = value;
  let multiline = false;
  $: multiline = string.includes("<br>");
</script>

<span class="text-green-200"
  >{#if multiline}
    """
  {:else}
    "{/if}<span
    class={multiline ? "block" : "inline"}
    contenteditable=""
    bind:innerHTML={string}
  />{#if multiline}
    """
  {:else}
    "
  {/if}</span
>
