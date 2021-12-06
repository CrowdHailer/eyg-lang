<script>
  import * as Expression from "../gen/eyg/ast/expression";
  import * as Sugar from "../gen/eyg/ast/sugar";

  import Let from "./Let.svelte";
  import Call from "./Call.svelte";
  import Row from "./Row.svelte";
  import Variable from "./Variable.svelte";
  import Function from "./Function.svelte";
  import Binary from "./Binary.svelte";
  import Provider from "./Provider.svelte";
  import Tuple from "./Tuple.svelte";

  export let expression;
  let metadata, tree;
  $: metadata = expression[0];
  $: tree = expression[1];
</script>

<!-- TODO instance of sugar, instance of is my case result -->
<!-- if is_ok(sugar) sugar[0 ] -->
{#if Sugar.is_variant(tree)}
<p
  tabindex="-1"
  class="border-2 border-transparent focus:border-indigo-300 outline-none rounded"
  data-editor={"p:" + metadata.position.toArray().join(",")}
>
  <span class="text-gray-500">data</span>
  <span
    tabindex="-1"
    class="border-2 border-transparent focus:border-indigo-300 outline-none rounded text-blue-800"
    data-editor={"p:" + metadata.position.toArray().concat(0).join(",")}
  >{tree.pattern.label}</span>

</p>

<svelte:self
  expression={tree.then}
  position={metadata.position.toArray().concat(2)}
/>

{:else if Sugar.is_data_variant(tree)}
<p
  tabindex="-1"
  class="border-2 border-transparent focus:border-indigo-300 outline-none rounded"
  data-editor={"p:" + metadata.position.toArray().join(",")}
>
  <span class="text-gray-500">data</span>
  <span class="text-blue-800">{tree.pattern.label}</span>({Object.keys(tree.value[1].pattern.elements)})

</p>

<svelte:self
  expression={tree.then}
  position={metadata.position.toArray().concat(2)}
/>

{:else if tree instanceof Expression.Tuple}
  <Tuple
    {metadata}
    elements={tree.elements}
  />
{:else if tree instanceof Expression.Binary}
  <Binary
    {metadata}
    value={tree.value}
  />
{:else if tree instanceof Expression.Let}
  <Let
    {metadata}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree instanceof Expression.Call}<Call
    {metadata}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree instanceof Expression.Row}
  <Row
  {metadata}
  fields={tree.fields}
  />
{:else if tree instanceof Expression.Variable}
  <Variable
    {metadata}
    label={tree.label}
    on:delete
  />
{:else if tree instanceof Expression.Function}
  <Function
    {metadata}
    pattern={tree.pattern}
    body={tree.body}
  />

{:else if tree instanceof Expression.Provider}
  <Provider
    {metadata}
    config={tree.config}
    generator={tree.generator}
  />
{:else}
  {JSON.stringify(tree)}
{/if}
