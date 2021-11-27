<script>
  export let position;
  export let metadata;
  export let value;
</script>

<span
  class="text-green-400 border-2 border-indigo-300 border-opacity-0 focus:border-opacity-100 outline-none rounded inline-block"
  tabindex="-1"
  data-position={"p" + position.join(",")}
  >{value}</span
>

<style>
  span {
    white-space: pre;
  }
  span::before {
    content: '"';
  }
  span::after {
    content: '"';
  }

</style>
