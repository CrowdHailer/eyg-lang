<script>
  import * as Editor from "../../../eyg/build/dev/javascript/eyg/dist/eyg/ast/editor";
  import * as Platform from "../../../eyg/build/dev/javascript/eyg/dist/platform/browser";

  export let source;
  let { spreadsheet } = Editor.eval$(Editor.init(source, Platform.harness()));
  console.log(spreadsheet);
  let state = spreadsheet.initial;

  function handleKeypress(event) {
    console.log(event.key);
    state = spreadsheet.loop([event.key, state]);
  }
</script>

<main tabindex="-1" on:keypress={handleKeypress}>
  <h1>Spreadsheet</h1>
  <p>
    {state}
  </p>
</main>
