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

  export let position;
  export let expression;
  let metadata, tree;
  $: metadata = expression[0];
  $: tree = expression[1];

  export let global;
</script>

<!-- {metadata.path.toArray()} -->
{#if tree instanceof Expression.Name}
  <Name
    {position}
    {metadata}
    on:edit
    {global}
    type={tree.type_}
    then={tree.then}
  />
{:else if tree instanceof Expression.Tuple}
  <Tuple
    {position}
    {metadata}
    on:edit
    {global}
    elements={tree.elements}
  />
{:else if tree instanceof Expression.Binary}
  <Binary
    {position}
    {metadata}
    on:edit
    {global}
    value={tree.value}
  />
{:else if tree instanceof Expression.Let}
  <Let
    {position}
    {metadata}
    on:edit
    {global}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree instanceof Expression.Call}<Call
    {position}
    {metadata}
    on:edit
    {global}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree instanceof Expression.Constructor}
  <Constructor on:edit {global} named={tree.named} variant={tree.variant} />
{:else if tree instanceof Expression.Row}
  <Ro
  {position}
  {metadata}
  on:edit
  {global}
  fields={tree.fields}
  />
{:else if tree instanceof Expression.Variable}
  <Variable
    {position}
    {metadata}
    on:edit
    {global}
    label={tree.label}
    on:delete
  />
{:else if tree instanceof Expression.Function}
  <Function
    {position}
    {metadata}
    on:edit
    {global}
    pattern={tree.pattern}
    body={tree.body}
  />
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
    {position}
    {metadata}
    on:edit
    {global}
    config={tree.config}
    generator={tree.generator}
  />
{:else}
  {JSON.stringify(tree)}
{/if}
