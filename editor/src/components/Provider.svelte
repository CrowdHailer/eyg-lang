<script>
  import * as Display from "../gen/eyg/editor/display";
  import Hole from "./Hole.svelte";
  import Expression from "./Expression.svelte";

  import * as Ast from "../gen/eyg/ast";
  export let metadata;
  export let generator;
  export let generated;
  export let config;

  // Can put exapand status on window object but that will not be reactive
  // Needs to be in meta data
  // Or have a reference to global editor state
  // DO I want the feature to be global?

  let generator_string, generator_metadata, config_metadata;
  $: (() => {
    let x = Display.for_provider_generator(generator, metadata);
    generator_string = x[0];
    generator_metadata = x[1];
  })();
  $: config_metadata = Display.for_provider_config(metadata);
</script>

{#if Ast.is_hole(generator)}
  <Hole {metadata} />
{:else if metadata.expanded}
  <Expression expression={generated} />
{:else}
  <span
    class="text-yellow-500 border-2 border-transparent outline-none rounded"
    class:border-red-500={metadata.errored && !Display.is_target(metadata)}
    class:border-indigo-300={Display.is_target(metadata)}
    data-editor={Display.marker(metadata)}
    ><span
      class="text-yellow-500 border-2 border-transparent outline-none rounded"
      class:border-red-500={generator_metadata.errored &&
        !Display.is_target(generator_metadata)}
      class:border-indigo-300={Display.is_target(generator_metadata)}
      data-editor={Display.marker(generator_metadata)}>{generator_string}</span
    ><span
      class="text-yellow-500 border-2 border-transparent outline-none rounded"
      class:border-red-500={config_metadata.errored &&
        !Display.is_target(config_metadata)}
      class:border-indigo-300={Display.is_target(config_metadata)}
      data-editor={Display.marker(config_metadata)}>&lt;{config}&gt</span
    ></span
  >
{/if}
