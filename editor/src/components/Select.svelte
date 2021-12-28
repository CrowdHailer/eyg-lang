<script>
  export let choices;
  export let makeSelection;
  export let cancelSelection;
  let filter;
  let remaining;
  $: remaining = choices.toArray().filter((c) => {
    if ((filter = "")) {
      return true;
    } else {
      return c.startsWith(filter);
    }
  });

  function handleKeydown(event) {
    console.log("keydown");
    if (event.metaKey || event.key == "Escape") {
      return true;
    }
    event.stopPropagation();
    try {
      if (event.key == "Enter" || event.key == " ") {
        let variable = Editor.in_scope(editor).toArray()[0];
        if (variable) {
          editor = Editor.handle_click(editor, "v:" + variable);
        }
        updateFocus(editor);
        event.preventDefault();
      }
    } catch (error) {
      console.error("Caught", error);
    }
  }

  function handleClick(event) {
    event.stopPropagation();
  }
  // TODO handle click key down
  // TODO remove v:
</script>

{filter}
{choices}
<div on:keydown={handleKeydown} on:click={handleClick}>
  <input
    class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
    id="filter"
    type="text"
    bind:value={filter}
  />
  <nav>
    variables:
    {#each remaining as choice, i}
      <button
        class="m-1 p-1 bg-blue-100 rounded border-black"
        class:border={i == 0}
        data-choice={choice}>{choice}</button
      >
    {/each}
  </nav>
</div>
