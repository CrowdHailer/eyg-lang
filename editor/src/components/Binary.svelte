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

<!-- auto enter to newline -->
{#if multiline}
  <span class="text-green-200">"""</span>
  <Indent>
    <!-- Make display block -->
    <div class="text-green-200" contenteditable="" bind:innerHTML={string} />
  </Indent>
  <span class="text-green-200">"""</span>
{:else}
  <span class="text-green-200"
    >"<span contenteditable="" bind:innerHTML={string} />"</span
  >
{/if}
