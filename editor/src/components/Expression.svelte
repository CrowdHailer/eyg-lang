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
</script>

{#if tree.type == "Name"}
  <Name type={tree.type_} then={tree.then} />
{:else if tree.type == "Let"}
  <Let pattern={tree.pattern} value={tree.value} then={tree.then} />
{:else if tree.type == "Call"}<Call
    function_={tree.function}
    with_={tree.with}
  />
{:else if tree.type == "Constructor"}
  <Constructor named={tree.named} variant={tree.variant} />
{:else if tree.type == "Row"}
  <Row fields={tree.fields} />
{:else if tree.type == "Variable"}
  <Variable label={tree.label} />
{:else if tree.type == "Function"}
  <Function for={tree.for} body={tree.body} />
{:else if tree.type == "Case"}
  <Case named={tree.named} value={tree.value} clauses={tree.clauses} />
{:else}
  foo
  {JSON.stringify(tree)}
{/if}
