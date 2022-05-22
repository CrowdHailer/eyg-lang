<script>
  export let output;
  export let input;
  export let active;
</script>

<h1>String2String</h1>
<input
  class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
  type="text"
  disabled={!active}
/>
{output}
