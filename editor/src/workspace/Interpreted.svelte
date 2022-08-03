<script>
  import * as Interpreter from "../../../eyg/build/dev/javascript/eyg/dist/eyg/interpreter/stepwise";

  export let source;
  //   console.log(Interpreter);
  $: (() => {
    if (source) {
      try {
        Interpreter.run_browser(source);
      } catch (error) {
        console.warn(error);
      }
    }
  })();
</script>

<!-- {JSON.stringify(source)} -->
<div id="the-id-for-dropping-html" />
