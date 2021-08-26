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

  export let tree;
  export let update_tree;
  export let path;
  export let count;
  export let error;
  let errorMessage;
  $: if (error && error[0].length === 0) {
    errorMessage = error[1];
  }
</script>

<!-- [{(path || []).concat([count]).join(",")}] -->
{#if tree.type == "Name"}
  <Name
    {update_tree}
    {path}
    {count}
    {error}
    type={tree.type_}
    then={tree.then}
  />
{:else if tree.type == "Binary"}
  <Binary {update_tree} {path} {count} {error} value={tree.value} />
{:else if tree.type == "Let"}
  <Let
    {update_tree}
    {path}
    {count}
    {error}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree.type == "Call"}<Call
    {update_tree}
    {path}
    {count}
    {error}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree.type == "Constructor"}
  <Constructor
    {update_tree}
    {path}
    {count}
    {error}
    named={tree.named}
    variant={tree.variant}
  />
{:else if tree.type == "Row"}
  <Row {update_tree} {path} {count} {error} fields={tree.fields} />
{:else if tree.type == "Variable"}
  <Variable {update_tree} {path} {count} {error} label={tree.label} />
{:else if tree.type == "Function"}
  <Function
    {update_tree}
    {path}
    {count}
    {error}
    for_={tree.for}
    body={tree.body}
  />
{:else if tree.type == "Case"}
  <Case
    {update_tree}
    {path}
    {count}
    {error}
    named={tree.named}
    value={tree.value}
    clauses={tree.clauses}
  />
{:else}
  foo
  {JSON.stringify(tree)}
{/if}
{#if errorMessage}
  <div class="absolute bg-red-100 border-t-2 border-red-300 py-1 px-4">
    {JSON.stringify(errorMessage)}
  </div>
{/if}
