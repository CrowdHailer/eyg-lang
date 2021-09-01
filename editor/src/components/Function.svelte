<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import * as AstBare from "../gen/eyg/ast";
  import * as Builders from "../gen/standard/builders";
  import { List } from "../gen/gleam";
  const Ast = Object.assign({}, AstBare, Builders);

  export let metadata;
  export let update_tree;
  // export let for_;
  export let body;
  // always tuple
  // for_ = $
  let arguments_;
  let main;
  $: (() => {
    let [a, b] = Ast.args_body(body);
    console.log(a);
    arguments_ = a.toArray();
    main = b;
  })();

  let newContent = "";
  function handleBlur() {
    let arg = newContent.trim().replace(" ", "_");
    if (arg) {
      let path = metadata.path;
      let newNode = Ast.function$(List.fromArray([...arguments_, arg]), main);
      console.log(newNode);
      update_tree(path, newNode);
      // thenFocus(path);
      newContent = "";
    }
  }
</script>

<!-- {JSON.stringify(arguments_)} -->
({arguments_.join(", ")}<span
  class="border-b border-gray-300 min-w-10 outline-none focus:border-gray-900 focus:border-2"
  contenteditable=""
  bind:textContent={newContent}
  on:blur={handleBlur}
/>) <strong>=></strong>
<Indent>
  <Expression expression={main} {update_tree} on:pinpoint on:depoint />
</Indent>

<style>
  span:focus::before {
    content: ", ";
  }
</style>
