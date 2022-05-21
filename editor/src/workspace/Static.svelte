<script>
  export let value;
</script>

<div class="p-6">
  <p>Static Value</p>
  <p class="bg-gray-200 p-1">
    <span>Output = </span><span>{value}</span>
  </p>
  <span
    class="inline-block w-36"
    class:bg-green-500={value == '"True"'}
    class:bg-red-500={!value == '"True"'}>Test</span
  >
</div>
