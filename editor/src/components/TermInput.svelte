<script>
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();

  export let initial;
  export let path;
  let content;
  $: content = initial;
  // onbeforeinput is best but complicated with all the different input types
  // this version looses charachter position, probably best to make beforeinput work and support only newest browsers.
  function handleInput(event) {
    let [first, ...rest] = content.split("<br>");
    let buffer;
    let returned = false;
    if (rest.length === 0) {
      buffer = first;
    } else {
      buffer = [first, ...rest].join("");
      returned = true;
    }
    content = buffer.replace(/\s/g, "");
    // Must replace content before bluring,
    // Svelte batches updates so the innerText is still the content value before validation
    if (returned) {
      event.target.blur();
      dispatch("enter", {});
    }
  }
  function handleBlur(event) {
    dispatch("change", {
      content: content,
    });
  }
</script>

<span
  class="outline-none"
  id="TODO not needed"
  contenteditable=""
  bind:innerHTML={content}
  on:input={handleInput}
  on:blur={handleBlur}
/>

<style>
  span:empty {
    display: inline-block;
    /* min-width: 1em; */
  }
  span:empty:focus {
    background-color: lightgrey;
  }
</style>
