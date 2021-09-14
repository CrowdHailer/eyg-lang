<script>
  import * as Expression from "../gen/eyg/ast/expression";
  import Let from "./Let.svelte";
  import Name from "./Name.svelte";
  import Call from "./Call.svelte";
  import Constructor from "./Constructor.svelte";
  import Row from "./Row.svelte";
  import Variable from "./Variable.svelte";
  import Function from "./Function.svelte";
  import Case from "./Case.svelte";
  import Binary from "./Binary.svelte";
  import Provider from "./Provider.svelte";
  import Tuple from "./Tuple.svelte";

  export let expression;
  let metadata, tree;
  $: metadata = expression[0];
  $: tree = expression[1];

  export let global;
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
</script>

<!-- {metadata.path.toArray()} -->
{#if tree instanceof Expression.Name}
  <Name {metadata} on:edit {global} type={tree.type_} then={tree.then} />
{:else if tree instanceof Expression.Tuple}
  <Tuple {metadata} on:edit {global} elements={tree.elements} />
{:else if tree instanceof Expression.Binary}
  <Binary {metadata} on:edit {global} value={tree.value} />
{:else if tree instanceof Expression.Let}
  <Let
    {metadata}
    on:edit
    {global}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree instanceof Expression.Call}<Call
    {metadata}
    on:edit
    {global}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree instanceof Expression.Constructor}
  <Constructor on:edit {global} named={tree.named} variant={tree.variant} />
{:else if tree instanceof Expression.Row}
  <Row {metadata} on:edit {global} fields={tree.fields} />
{:else if tree instanceof Expression.Variable}
  <Variable {metadata} on:edit {global} label={tree.label} on:delete />
{:else if tree instanceof Expression.Function}
  <Function {metadata} on:edit {global} for_={tree.for} body={tree.body} />
{:else if tree instanceof Expression.Case}
  <Case
    on:edit
    {global}
    named={tree.named}
    value={tree.value}
    clauses={tree.clauses}
  />
{:else if tree instanceof Expression.Provider}
  <Provider
    {metadata}
    on:edit
    {global}
    config={tree.config}
    generator={tree.generator}
    on:deletebackwards
  />
{:else}
  {JSON.stringify(tree)}
{/if}
