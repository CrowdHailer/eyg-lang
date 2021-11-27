<script>
  export let position;
  export let metadata;
</script>

<span
  class="border-2 border-gray-300 focus:border-indigo-300 outline-none rounded inline-block"
  tabindex="-1"
  data-editor={"p:" + position.join(",")}
></span>


<style>
  span:empty {
    display: inline-block;
    min-width: 1em;
  }
  span {
    white-space: pre;
  }
  span::before {
    content: ' ';
  }
  span::after {
    content: ' ';
  }
</style>
