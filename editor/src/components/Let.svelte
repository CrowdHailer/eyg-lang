<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import * as Edit from "../gen/eyg/ast/edit";
  import * as Option from "../gen/gleam/option";
  import Pattern from "./Pattern.svelte";

  export let metadata;
  export let pattern;
  export let value;
  export let then;
  export let global;

  function handleKeydown(event) {
    const { key, ctrlKey } = event;
    let action = Edit.shotcut_for_let(key, ctrlKey);
    Option.map(action, (action) => {
      let edit = Edit.edit(action, metadata.path);
      event.preventDefault();
      event.stopPropagation();
      dispatch("edit", edit);
    });
    event.stopPropagation();
  }
</script>

<p
  tabindex="-1"
  id={Ast.path_to_id(metadata.path)}
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  on:keydown={handleKeydown}
>
  <span class="text-yellow-400">let</span>
  <Pattern {pattern} {metadata} {global} />
  =
  <Expression expression={value} on:edit {global} />
  <ErrorNotice type_={metadata.type_} />
</p>
<Expression expression={then} on:edit {global} />
