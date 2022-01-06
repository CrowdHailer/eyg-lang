<script>
  export let choices;
  export let makeSelection;
  // cancel selection is handled by the Escape key being caught at the editor level
  // export let cancelSelection;

  let filter = "";
  let remaining;
  $: remaining = choices.toArray().filter((c) => {
    if (filter == "") {
      return true;
    } else {
      return c.startsWith(filter);
    }
  });

  function handleKeydown(event) {
    if (event.metaKey || event.key == "Escape") {
      return true;
    }
    event.stopPropagation();
    if (event.key == "Enter" || event.key == " ") {
      let value = remaining[0];
      makeSelection(value);
      event.preventDefault();
    }
  }

  function handleClick(event) {
    event.stopPropagation();
    let choice = clickToChoice(event);
    if (choice !== undefined) {
      makeSelection(choice);
    }
  }

  function clickToChoice(event) {
    let element = event.target.closest("[data-choice]");
    if (element) {
      return element.dataset.choice;
    }
  }
</script>

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
