<script>
  import { createEventDispatcher } from "svelte";
  import { List } from "../gen/gleam";
  const dispatch = createEventDispatcher();
  import ErrorNotice from "./ErrorNotice.svelte";
  export let position;
  export let metadata;
  export let global;
  export let value;

  let updated;
  $: updated = value;
  let multiline = false;
  let active = false;
  let self;

  function handleBlur(event) {
    if (active) {
      active = false;
      self.focus();
      dispatch("contentedited", {
        position: List.fromArray(position),
        content: updated,
      });
    }
  }

  function handleInput(event) {
    updated = event.target.innerHTML;

    // cant use {@html keeps moving cusor to beginning}
    // Needs to handle any case that only ends in new line needs to not render updated because that
    // if (updated === "<br>") {
    //   value = "";
    // }
    // whitespace pre change br to \n
    multiline = updated.includes("\n");
  }

  // keypress is deprecated
  function handleKeydown(event) {
    const { key } = event;
    if (active) {
      if (key === "Escape") {
        self.blur();
      } else {
      }
      event.stopPropagation();
    } else {
      if (key === "i") {
        active = true;
        var range = document.createRange();
        var sel = window.getSelection();

        // https://stackoverflow.com/questions/6249095/how-to-set-caretcursor-position-in-contenteditable-element-div
        var node = self.childNodes[0];
        range.setStart(node, node.length);
        range.collapse(true);

        sel.removeAllRanges();
        sel.addRange(range);
      } else {
      }
      event.preventDefault();
    }
  }
</script>

<!-- Text areas don't resize as wanted, onchange doesn't work on contenteditable -->
<!-- Need to turn contenteditable on and off to no have cursor but cant use bind:innerHTML if contenteditable is dynamic -->
<span
  class="text-green-400 border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded inline-block"
  class:multiline
  tabindex="-1"
  data-position={"p" + position.join(",")}
  contenteditable={active}
  bind:this={self}
  on:blur={handleBlur}
  on:input={handleInput}
  on:keydown={handleKeydown}>{value}</span
><ErrorNotice type_={metadata.type_} />

<style>
  span {
    white-space: pre;
  }
  span::before {
    content: '"';
  }
  span::after {
    content: '"';
  }
  /* https://stackoverflow.com/questions/9062988/newline-character-sequence-in-css-content-property */
  span.multiline::before {
    content: '"""\00000a';
  }
  span.multiline::after {
    content: '"""';
  }
</style>
