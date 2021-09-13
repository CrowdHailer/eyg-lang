<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import { tick, createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
  import * as Ast from "../gen/eyg/ast";
  import * as Edit from "../gen/eyg/ast/edit";
  import * as Option from "../gen/gleam/option";
  export let metadata;
  export let global;
  export let value;

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
  function handleKeydown(event) {
    const { key, ctrlKey } = event;
    let action;
    if ((key === "Delete" || key === "Backspace") && string === "") {
      action = Edit.clear_action();
    } else {
      action = Edit.shotcut_for_binary(key, ctrlKey);
    }
    Option.map(action, (action) => {
      let edit = Edit.edit(action, metadata.path);
      event.preventDefault();
      event.stopPropagation();
      dispatch("edit", edit);
    });
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
