<script>
  import * as Expression from "../gen/eyg/ast/expression";
  import Let from "./Let.svelte";
  import Call from "./Call.svelte";
  import Row from "./Row.svelte";
  import Variable from "./Variable.svelte";
  import Function from "./Function.svelte";
  import Binary from "./Binary.svelte";
  import Provider from "./Provider.svelte";
  import Tuple from "./Tuple.svelte";

  export let position;
  export let expression;
  let metadata, tree;
  $: metadata = expression[0];
  $: tree = expression[1];
</script>

{#if tree instanceof Expression.Tuple}
  <Tuple
    {position}
    {metadata}
    elements={tree.elements}
  />
{:else if tree instanceof Expression.Binary}
  <Binary
    {position}
    {metadata}
    value={tree.value}
  />
{:else if tree instanceof Expression.Let}
  <Let
    {position}
    {metadata}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree instanceof Expression.Call}<Call
    {position}
    {metadata}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree instanceof Expression.Row}
  <Row
  {position}
  {metadata}
  fields={tree.fields}
  />
{:else if tree instanceof Expression.Variable}
  <Variable
    {position}
    {metadata}
    label={tree.label}
    on:delete
  />
{:else if tree instanceof Expression.Function}
  <Function
    {position}
    {metadata}
    pattern={tree.pattern}
    body={tree.body}
  />

{:else if tree instanceof Expression.Provider}
  <Provider
    {position}
    {metadata}
    config={tree.config}
    generator={tree.generator}
  />
{:else}
  {JSON.stringify(tree)}
{/if}
