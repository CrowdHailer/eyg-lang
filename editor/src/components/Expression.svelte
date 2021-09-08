<script>
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

  export let update_tree;
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
</script>

<!-- {metadata.path.toArray()} -->
{#if tree.type == "Name"}
  <Name {metadata} {update_tree} type={tree.type_} then={tree.then} />
{:else if tree.type == "Tuple"}
  <Tuple {metadata} {update_tree} elements={tree.elements} />
{:else if tree.type == "Binary"}
  <Binary {metadata} {update_tree} value={tree.value} />
{:else if tree.type == "Let"}
  <Let
    {metadata}
    {update_tree}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree.type == "Call"}<Call
    {metadata}
    {update_tree}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree.type == "Constructor"}
  <Constructor {update_tree} named={tree.named} variant={tree.variant} />
{:else if tree.type == "Row"}
  <Row {update_tree} fields={tree.fields} />
{:else if tree.type == "Variable"}
  <Variable {metadata} {update_tree} label={tree.label} on:delete />
{:else if tree.type == "Function"}
  <Function {metadata} {update_tree} for_={tree.for} body={tree.body} />
{:else if tree.type == "Case"}
  <Case
    {update_tree}
    named={tree.named}
    value={tree.value}
    clauses={tree.clauses}
  />
{:else if tree.type == "Provider"}
  <Provider
    {metadata}
    {update_tree}
    generator={tree.generator}
    on:deletebackwards
  />
{:else}
  foo
  {JSON.stringify(tree)}
{/if}
