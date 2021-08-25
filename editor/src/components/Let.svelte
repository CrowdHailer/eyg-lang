<script>
  import Expression from "./Expression.svelte";
  export let pattern;
  export let value;
  export let then;
  export let update_tree;
  export let path;
  export let count;

  function removeLet(path) {
    update_tree(path, then);
  }
  function hello() {
    console.log("Yo");
  }
  function pressed(event) {
    // TODO if dirty or not
    if (event.code == "Enter") {
      // console.log("new line");
      path = path.concat(count + 1);
      // update_tree(path, { type: "Binary", value: "new" });
      update_tree(path, {
        type: "Let",
        pattern: { type: "Variable", label: "_" },
        value: { type: "Binary", value: "xx" },
        then: then,
      });
    } else {
      console.log(event);
      console.log(path.concat(count));
    }
  }
</script>

<p>
  <span tabindex="0" on:focus={hello} on:keypress={pressed}>
    <span class="text-yellow-400" on:click={() => removeLet(path.concat(count))}
      >let</span
    >
    {#if pattern.type == "Variable"}
      <!-- probably make this not focusable input at the bottom -->
      <input
        class="bg-black inline"
        type="text"
        value={pattern.label}
        on:change={pressed}
      />
    {:else if pattern.type == ""}
      bb{:else}{pattern}{/if} =
  </span><Expression
    tree={value}
    {update_tree}
    path={path?.concat(count)}
    count={0}
  />
</p>
<Expression tree={then} {path} count={count + 1} {update_tree} />
