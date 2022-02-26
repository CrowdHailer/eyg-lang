<script>
  import * as Expression from "../../../eyg/build/dev/javascript/eyg/dist/eyg/ast/expression";

  import Let from "./Let.svelte";
  import Call from "./Call.svelte";
  import Case from "./Case.svelte";
  import Record from "./Record.svelte";
  import Variable from "./Variable.svelte";
  import Function from "./Function.svelte";
  import Binary from "./Binary.svelte";
  import Hole from "./Hole.svelte";
  import Provider from "./Provider.svelte";
  import Tuple from "./Tuple.svelte";

  import Tagged from "./Tagged.svelte";

  export let expression;
  let metadata, tree;
  $: metadata = expression[0];
  $: tree = expression[1];
</script>

{#if tree instanceof Expression.Tuple}
  <Tuple {metadata} elements={tree.elements} />
{:else if tree instanceof Expression.Binary}
  <Binary {metadata} value={tree.value} />
{:else if tree instanceof Expression.Let}
  <Let {metadata} pattern={tree.pattern} value={tree.value} then={tree.then} />
{:else if tree instanceof Expression.Call}
  <Call {metadata} function_={tree.function} with_={tree.with} />
{:else if tree instanceof Expression.Case}
  <Case {metadata} value={tree.value} branches={tree.branches} />
{:else if tree instanceof Expression.Record}
  <Record {metadata} fields={tree.fields} />
  <!-- {#if tree instanceof Expression.Tagged}
  <Tagged {metadata} tag={tree.tag} value={tree.value} /> -->
{:else if tree instanceof Expression.Variable}
  <Variable {metadata} label={tree.label} on:delete />
{:else if tree instanceof Expression.Function}
  <Function {metadata} pattern={tree.pattern} body={tree.body} />
{:else if tree instanceof Expression.Hole}
  <Hole {metadata} />
{:else if tree instanceof Expression.Provider}
  <Provider
    {metadata}
    config={tree.config}
    generator={tree.generator}
    generated={tree.generated}
  />
{:else}
  {JSON.stringify(tree)}
{/if}
