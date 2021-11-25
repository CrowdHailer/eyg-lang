<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import * as Editor from "../gen/eyg/ast/editor";

  export let position;
  export let metadata;
  export let fields;
  export let global;

  let multiline = false;
  multiline = Editor.multiline(fields)
</script>


<Indent {multiline}>
  {#each fields.toArray() as [label, value], i}
    <span class="text-purple-600">{label}</span><span class="text-gray-500"
      >:</span
    >
    <Expression position={position.concat(i)} expression={value} {global} />{#if i < fields.toArray().length - 1},{/if}{#if multiline}<br />{/if}
  {/each}
</Indent>
<ErrorNotice type_={metadata.type_} />
