<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  import { List } from "../gen/gleam";
  const Ast = Object.assign({}, AstBare, Builders);

  export let metadata;
  export let global;
  // export let for_;
  export let body;
  // always tuple
  // for_ = $
  let arguments_;
  let main;
  $: (() => {
    let [a, b] = Ast.args_body(body);
    arguments_ = a.toArray();
    main = b;
  })();

  let newContent = "";
  function handleBlur() {
    let arg = newContent.trim().replace(" ", "_");
    if (arg) {
      let path = metadata.path;
      let newNode = Ast.function$(List.fromArray([...arguments_, arg]), main);
      global.update_tree(path, newNode);
      // thenFocus(path);
      newContent = "";
    }
  }

  function handleDeletebackwards(_event) {
    let path = metadata.path;
    global.update_tree(path, Ast.hole());
    thenFocus(path);
  }
</script>

({arguments_.join(", ")}<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  contenteditable=""
  bind:textContent={newContent}
  on:blur={handleBlur}
/>) <strong>=></strong>
<Indent>
  <Expression
    expression={main}
    on:edit
    {global}
    on:deletebackwards={handleDeletebackwards}
  />
</Indent>
<ErrorNotice type_={metadata.type_} />

<style>
  span:focus::after {
    content: ", ";
  }
</style>
