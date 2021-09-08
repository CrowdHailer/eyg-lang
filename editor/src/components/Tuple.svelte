<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import { tick } from "svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import Hole from "./Hole.svelte";
  export let metadata;
  export let elements;
  export let update_tree;

  function thenFocus(path) {
    tick().then(() => {
      let pathId = "p" + path.toArray().join(",");
      let element = document.getElementById(pathId);
      element?.focus();
    });
  }
  function handleDeletebackwards(_event) {
    let len = elements.toArray().length;
    if (len) {
      thenFocus(Ast.append_path(len - 1));
    } else {
      update_tree(metadata.path, Ast.hole());
      thenFocus(metadata.path);
    }
  }
</script>

[{#each elements.toArray() as element, i}
  <Expression expression={element} {update_tree} />,&nbsp;
{/each}
<Hole
  metadata={Object.assign({}, metadata, {
    path: Ast.append_path(metadata.path, elements.toArray().length),
  })}
  {update_tree}
  on:deletebackwards={handleDeletebackwards}
/>]
<ErrorNotice type_={metadata.type_} />
