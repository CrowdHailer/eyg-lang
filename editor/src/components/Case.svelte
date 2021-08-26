<script>
  import Expression from "./Expression.svelte";
  import Indent from "./Indent.svelte";
  import TermInput from "./TermInput.svelte";
  export let named;
  export let value;
  export let clauses;
  export let update_tree;
  export let path;
  export let count;
  export let error;

  let CaseError, subjectError;
  let clauseErrors = {};
  $: if (error && error[0].length == 0) {
    CaseError = error[1];
  } else if (error && error[0].length == 1 && error[0] == 0) {
    subjectError = [[], error[1]];
  } else if (error && error[0].length) {
    let [location, reason] = error;
    let [_, k, ...rest] = location;
    clauseErrors = Object.fromEntries([[k, [rest, reason]]]);
  } else {
    subjectError = undefined;
    clauseErrors = {};
  }
</script>

<span class="text-yellow-400" title={named}
  >case <TermInput initial={named} /></span
>
<Expression
  tree={value}
  path={path?.concat(count)}
  count={0}
  {update_tree}
  error={subjectError}
/>
<Indent>
  {#each clauses.toArray() as [variant, _variable, then], i}
    {variant}({then.pattern.elements.toArray().join(", ")})
    <span class="font-bold">=></span>
    <Expression
      tree={then.then}
      path={path?.concat(count)}
      count={i + 1}
      {update_tree}
      error={clauseErrors[i + 1]}
    /><br />
  {/each}
</Indent>
