<script>
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();

  import { binary } from "../gen/eyg/ast";

  import Indent from "./Indent.svelte";
  export let value;
  export let metadata;

  export let update_tree;

  let string = value;
  let multiline = false;
  $: multiline = string.includes("<br>");
  function handleFocus() {}
  function handleBlur() {
    if (value == string) {
      console.log("no change");
    } else {
      update_tree(metadata.path, binary(string));
    }
  }
</script>

<span class="text-green-400"
  >{#if multiline}
    """
  {:else}
    "{/if}<span
    id="p{metadata.path.toArray().join(',')}"
    class={multiline ? "block" : "inline"}
    contenteditable=""
    on:focus={handleFocus}
    on:blur={handleBlur}
    bind:innerHTML={string}
  />{#if multiline}
    """
  {:else}
    "
  {/if}</span
>
