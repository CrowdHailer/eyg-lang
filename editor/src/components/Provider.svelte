<script>
  import { tick } from "svelte";
  import ErrorNotice from "./ErrorNotice.svelte";
  import Hole from "./Hole.svelte";
  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);
  import * as Pattern from "../gen/eyg/ast/pattern";
  import { resolve } from "../gen/eyg/typer/monotype";
  import { List } from "../gen/gleam";
  export let metadata;
  export let global;
  export let config;
  export let generator;

  // function thenFocus(path) {
  //   tick().then(() => {
  //     let element = document.getElementById(pathId);
  //     element?.focus();
  //   });
  // }

  function handleBlur() {
    let path = metadata.path;
    let newNode = Ast.provider(config, generator);
    global.update_tree(path, newNode);
    // thenFocus(path);
  }

  let self;
  function handleKeydown(event) {
    if (event.target === self) {
      if (event.key === "(") {
        event.preventDefault();
        // console.log(global.typer);
        // console.log(resolve(metadata.type_["0"], global.typer.substitutions));
        let node = Ast.provider(config, generator);
        let path = metadata.path;
        let newNode = Ast.call(node, List.fromArray([]));
        global.update_tree(path, newNode);
        thenFocus(Ast.append_path(path), 1);
      } else if (event.key == "=") {
        event.preventDefault();

        let node = Ast.provider(config, generator);
        let path = metadata.path;
        let newNode = Ast.let_(Pattern.variable(""), node, Ast.hole());
        global.update_tree(path, newNode);
        thenFocus(path);
      } else {
      }
    } else {
    }
  }
</script>

{#if Ast.is_hole(generator)}
  <Hole {metadata} on:edit {global} required={true} />
{:else}
  <span
    bind:this={self}
    class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
    tabindex="0"
    on:keydown={handleKeydown}
  >
    format&lt;"<span
      class="outline-none"
      contenteditable=""
      bind:textContent={config}
      id={Ast.path_to_id(metadata.path)}
      on:blur={handleBlur}
    />"&gt;</span
  >{/if}<ErrorNotice type_={metadata.type_} />
