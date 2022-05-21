<script>
  export let result;
</script>

<div class="p-6">
  <p>TestSuite</p>

  <span
    class="inline-block w-36"
    class:bg-green-500={result == "True"}
    class:bg-red-500={!result == "True"}>Result</span
  >
</div>
