<script>
  import * as Display from "../gen/eyg/editor/display";
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import Pattern from "./Pattern.svelte";

  export let metadata;
  export let value;
  export let branches;

  let expand = false;
  $: expand = Display.show_expression(metadata);
</script>

<span
  class="border-2 border-transparent outline-none rounded"
  class:border-red-500={metadata.errored && !Display.is_target(metadata)}
  class:border-indigo-300={Display.is_target(metadata)}
  data-editor={Display.marker(metadata)}
>
  <span class="text-gray-500">match</span>
  <Expression expression={value} />
  {#if expand}
    <Indent>
      {#each Display.for_branches(branches, metadata).toArray() as [branch_meta, name_meta, name, pattern_meta, pattern, then]}
        <div
          class="border-2 border-transparent outline-none rounded"
          class:border-red-500={branch_meta.errored &&
            !Display.is_target(branch_meta)}
          class:border-indigo-300={Display.is_target(branch_meta)}
          data-editor={Display.marker(branch_meta)}
        >
          <span
            class="text-blue-800 font-bold border-2 border-transparent outline-none rounded"
            class:border-red-500={name_meta.errored &&
              !Display.is_target(name_meta)}
            class:border-indigo-300={Display.is_target(name_meta)}
            data-editor={Display.marker(name_meta)}>{name}</span
          >
          <Pattern {pattern} metadata={pattern_meta} />
          <span>=></span>
          {#if Display.is_multiexpression(then)}
            <Indent>
              <Expression expression={then} />
            </Indent>
          {:else}
            <Expression expression={then} />
          {/if}
        </div>
      {/each}
    </Indent>
  {:else}
    <span class="text-gray-500" data-editor="{Display.marker(metadata)},1"
      >&lbrace; ... &rbrace;</span
    >
  {/if}
</span>
