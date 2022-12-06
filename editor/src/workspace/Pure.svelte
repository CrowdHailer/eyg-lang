<script>
  import * as Option from "../../../eyg/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
  import { log } from "../../../eyg/build/dev/javascript/gleam_stdlib/gleam_stdlib.mjs";

  export let state;
  //   $: console.log(code);

  //   let init;
  //   let state;
  let rendered;

  $: (function () {
    if (state instanceof Option.Some) {
      console.log(state);
      let s = state[0][0];
      let render = state[0][1];
      rendered = render(s);
      //       init = code[0].init;
      //       console.log(init);
      //       state = init({
      //         keypress: (handle) => {
      //           console.log(handle);
      //           setTimeout(() => {
      //             console.log("timed out");
      //             state = handle(["X", state]);
      //             console.log(state, "====");
      //           }, 2000);
      //           return (cont) => {
      //             return cont([]);
      //           };
      //         },
      //       });
      //       render = code[0].render;
      //     } else {
      //       init = undefined;
      //       render = undefined;
    }
    //     // console.log(init, render);
  })();
</script>

{rendered}
