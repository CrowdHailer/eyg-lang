<script>
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
  import ErrorNotice from "./ErrorNotice.svelte";

  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  const Ast = Object.assign({}, AstBare, Builders);

  export let position;
  export let metadata;
  export let global;

  let active = false
  function handleKeydown(event) {

  }

</script>

<span
  class="border-2 border-gray-300 focus:border-indigo-300 outline-none rounded inline-block"
  tabindex="-1"
  contenteditable={active}
  data-position={"p" + position.join(",")}
  on:keydown={handleKeydown}
></span>

<ErrorNotice type_={metadata.type_} />

<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
  span {
    white-space: pre;
  }
  span::before {
    content: ' ';
  }
  span::after {
    content: ' ';
  }
</style>
