<script>
  import { Error } from "../gen/gleam";
  export let type_;
</script>

{#if type_ instanceof Error}
  <div
    class=" bg-red-100 border-t-2 border-red-300 py-1 px-4 absolute left-0 right-0 mx-10 mt-6"
  >
    {JSON.stringify(type_[0])}
  </div>
{/if}
