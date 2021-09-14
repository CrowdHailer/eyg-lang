<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import * as Ast from "../gen/eyg/ast";
  import Pattern from "./Pattern.svelte";

  export let position;
  export let metadata;
  export let pattern;
  export let value;
  export let then;
  export let global;
</script>

<p
  tabindex="-1"
  id={Ast.path_to_id(metadata.path)}
  class="border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  data-position={"p" + position.join(",")}
>
  <span class="text-yellow-400">let</span>
  <Pattern {pattern} {metadata} {global} position={position.concat(0)} />
  =
  <Expression expression={value} {global} position={position.concat(1)} />
  <ErrorNotice type_={metadata.type_} />
</p>
<Expression expression={then} {global} position={position.concat(2)} />
