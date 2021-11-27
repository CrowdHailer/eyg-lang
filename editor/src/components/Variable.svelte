<script>

  export let position;
  export let metadata;
  export let label;
  export let global;
</script>

<!-- Don't edit delte replace with autocomplete -->
<span
  class="outline-none text-blue-500 border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded"
  tabindex="-1"
  data-position={"p" + position.join(",")}>{label}</span
>

<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
</style>
