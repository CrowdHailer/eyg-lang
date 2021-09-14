<script>
  import ErrorNotice from "./ErrorNotice.svelte";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";

  export let metadata;
  export let global;
  export let pattern;
  export let body;
  console.log(global, "ff");
</script>

<Pattern {pattern} {metadata} {global} /> <strong>=></strong>
<Indent>
  <Expression expression={body} on:edit {global} />
</Indent>
<ErrorNotice type_={metadata.type_} />
