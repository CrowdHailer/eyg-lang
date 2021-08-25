<script>
  import Let from "./Let.svelte";
  import Name from "./Name.svelte";
  import Call from "./Call.svelte";
  import Constructor from "./Constructor.svelte";
  import Row from "./Row.svelte";
  import Variable from "./Variable.svelte";
  import Function from "./Function.svelte";
  import Case from "./Case.svelte";

  export let tree;
  export let update_tree;
  export let path;
  export let count;
</script>

<!-- [{(path || []).concat([count]).join(",")}] -->
{#if tree.type == "Name"}
  <Name {update_tree} {path} {count} type={tree.type_} then={tree.then} />
{:else if tree.type == "Let"}
  <Let
    {update_tree}
    {path}
    {count}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree.type == "Call"}<Call
    {update_tree}
    {path}
    {count}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree.type == "Constructor"}
  <Constructor
    {update_tree}
    {path}
    {count}
    named={tree.named}
    variant={tree.variant}
  />
{:else if tree.type == "Row"}
  <Row {update_tree} {path} {count} fields={tree.fields} />
{:else if tree.type == "Variable"}
  <Variable {update_tree} {path} {count} label={tree.label} />
{:else if tree.type == "Function"}
  <Function {update_tree} {path} {count} for_={tree.for} body={tree.body} />
{:else if tree.type == "Case"}
  <Case
    {update_tree}
    {path}
    {count}
    named={tree.named}
    value={tree.value}
    clauses={tree.clauses}
  />
{:else}
  foo
  {JSON.stringify(tree)}
{/if}
