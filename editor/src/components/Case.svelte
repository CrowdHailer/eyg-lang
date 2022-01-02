<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";

  export let metadata;
  export let value;
  export let branches;
</script>

<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
>
  <span class="text-gray-500">match</span>
  <Expression expression={value} />
  <Indent>
    {#each branches.toArray() as [name, pattern, then]}
      <div>
        <span class="text-blue-800">{name}</span>
        <Pattern {pattern} {metadata} />
        <span>=></span>
        <Expression expression={then} />
      </div>
    {/each}
  </Indent>
</span>
