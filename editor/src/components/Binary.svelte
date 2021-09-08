<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import { tick } from "svelte";
  import * as Ast from "../gen/eyg/ast";
  export let metadata;
  export let global;
  export let value;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element?.focus();
    });
  }

  let string = value;
  $: if (string === "<br>") {
    string = "";
  }
  let multiline = false;
  $: multiline = string.includes("<br>");
  function handleBlur() {
    if (value !== string) {
      global.update_tree(
        metadata.path,
        Ast.binary(string.replace("<br>", "\n"))
      );
    }
  }
  // keypress is deprecated
  function handleKeydown({ key }) {
    if ((key === "Delete" || key === "Backspace") && string === "") {
      global.update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    }
  }
</script>

<span class="text-green-400"
  >{#if multiline}
    """
  {:else}
    "{/if}<span
    id="p{metadata.path.toArray().join(',')}"
    class="{multiline ? 'block' : 'inline'} outline-none"
    contenteditable=""
    on:blur={handleBlur}
    on:keydown={handleKeydown}
    bind:innerHTML={string}
  />{#if multiline}
    """
  {:else}
    "
  {/if}</span
>
<ErrorNotice type_={metadata.type_} />
