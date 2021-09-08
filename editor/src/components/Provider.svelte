<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Hole from "./Hole.svelte";
  import * as Ast from "../gen/eyg/ast";
  export let metadata;
  export let update_tree;
  export let config;
  export let generator;

  function handleBlur() {
    let path = metadata.path;
    let newNode = Ast.provider(config, generator);
    update_tree(path, newNode);
    // thenFocus(path);
  }
</script>

{#if Ast.is_hole(generator)}
  <Hole {metadata} {update_tree} required={true} on:deletebackwards />
{:else}
  format&lt;"<span
    class="outline-none"
    contenteditable=""
    bind:textContent={config}
    id={Ast.path_to_id(metadata.path)}
    on:blur={handleBlur}
  />"&gt;
{/if}
<ErrorNotice type_={metadata.type_} />
