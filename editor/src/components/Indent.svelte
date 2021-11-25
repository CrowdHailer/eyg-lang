<script>
  export let multiline = true
</script>

<span class="text-gray-600">&lbrace;</span>
<div class:pl-4={multiline} class:inline={!multiline}>
  <slot />
</div>
<span class="text-gray-600">&rbrace;</span>
