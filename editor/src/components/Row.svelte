<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import * as Editor from "../gen/eyg/ast/editor";
  import * as Typer from "../gen/eyg/typer";

  export let position;
  export let metadata;
  export let fields;

  let multiline = false;
  multiline = Editor.multiline(fields)

  let error = false
  $: error = Typer.is_error(metadata)
</script>

<span
  tabindex="-1"
  data-editor={"p:" + position.join(",")}
  class="border-2 border-white focus:border-indigo-300 outline-none rounded"
  class:border-red-500={error}><Indent {multiline}>
  {#each fields.toArray() as [label, value], i}
    <span
      tabindex="-1"
      class="text-purple-600 border-2 border-white focus:border-indigo-300 outline-none rounded"
      data-editor={"p:" + position.concat(i).join(",")}>
      <span
        tabindex="-1"
        class="text-purple-600 border-2 border-white focus:border-indigo-300 outline-none rounded"
        data-editor={"p:" + position.concat(i, 0).join(",")}
        >{label}</span><span class="text-gray-500"
        >:</span
      >
      <Expression position={position.concat(i, 1)} expression={value} />{#if i < fields.toArray().length - 1},{/if}{#if multiline}<br />{/if}
    </span>
  {/each}
</Indent></span>
