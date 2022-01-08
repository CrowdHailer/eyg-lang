<script>
  import * as Gleam from "../gen/gleam";
  import * as Expression from "../gen/eyg/ast/expression";
  import * as Sugar from "../gen/eyg/ast/sugar";

  import Let from "./Let.svelte";
  import Call from "./Call.svelte";
  import Case from "./Case.svelte";
  import Row from "./Row.svelte";
  import Variable from "./Variable.svelte";
  import Function from "./Function.svelte";
  import Binary from "./Binary.svelte";
  import Provider from "./Provider.svelte";
  import Tuple from "./Tuple.svelte";

  import Tag from "./Tag.svelte";

  export let expression;
  let metadata, tree, sugar;
  $: metadata = expression[0];
  $: tree = expression[1];
  $: sugar = (function (params) {
    let result = Sugar.match(tree);
    if (result instanceof Gleam.Ok) {
      return result[0];
    }
  })();
</script>

{#if sugar instanceof Sugar.Tag}
  <Tag {metadata} name={sugar.name} />
{:else if tree instanceof Expression.Tuple}
  <Tuple {metadata} elements={tree.elements} />
{:else if tree instanceof Expression.Binary}
  <Binary {metadata} value={tree.value} />
{:else if tree instanceof Expression.Let}
  <Let {metadata} pattern={tree.pattern} value={tree.value} then={tree.then} />
{:else if tree instanceof Expression.Call}
  <Call {metadata} function_={tree.function} with_={tree.with} />
{:else if tree instanceof Expression.Case}
  <Case {metadata} value={tree.value} branches={tree.branches} />
{:else if tree instanceof Expression.Row}
  <Row {metadata} fields={tree.fields} />
{:else if tree instanceof Expression.Variable}
  <Variable {metadata} label={tree.label} on:delete />
{:else if tree instanceof Expression.Function}
  <Function {metadata} pattern={tree.pattern} body={tree.body} />
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
