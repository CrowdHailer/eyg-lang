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

  export let expression;
  let metadata, tree;
  $: metadata = expression[0];
  $: tree = expression[1];

  export let update_tree;
</script>

<!-- {metadata.path.toArray()} -->
{#if tree.type == "Name"}
  <Name {update_tree} type={tree.type_} then={tree.then} />
{:else if tree.type == "Binary"}
  <Binary {update_tree} value={tree.value} />
{:else if tree.type == "Let"}
  <Let
    {update_tree}
    pattern={tree.pattern}
    value={tree.value}
    then={tree.then}
  />
{:else if tree.type == "Call"}<Call
    {update_tree}
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree.type == "Constructor"}
  <Constructor {update_tree} named={tree.named} variant={tree.variant} />
{:else if tree.type == "Row"}
  <Row {update_tree} fields={tree.fields} />
{:else if tree.type == "Variable"}
  <Variable {update_tree} label={tree.label} />
{:else if tree.type == "Function"}
  <Function {update_tree} for_={tree.for} body={tree.body} />
{:else if tree.type == "Case"}
  <Case
    {update_tree}
    named={tree.named}
    value={tree.value}
    clauses={tree.clauses}
  />
{:else if tree.type == "Provider"}
  <Provider {metadata} {update_tree} id={tree.id} generator={tree.generator} />
{:else}
  foo
  {JSON.stringify(tree)}
{/if}
<!-- {#if errorMessage}
  <div class="absolute bg-red-100 border-t-2 border-red-300 py-1 px-4">
    {JSON.stringify(errorMessage)}
  </div>
{/if} -->
