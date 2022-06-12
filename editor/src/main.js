// import { main } from "../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/main";
import { deploy } from "../../eyg/build/dev/javascript/eyg/dist/eyg/workspace/ui.mjs";

import App from "./Workspace.svelte";

var deployPage = window.location.pathname.slice(1) == "deploy";
var app;
if (deployPage) {
  deploy(window.location.search.slice(1)).then(({ init, update, render }) => {
    document.body.innerHTML =
      '<div class="w-full min-h-screen h-full bg-gray-100 flex"></div>';
    let container = document.querySelector("div");
    console.log(container);
    let state = init([]);
    container.innerHTML = render(state);

    window.addEventListener("click", function () {
      state = update(state);
      container.innerHTML = render(state);
    });
  });
} else {
  app = new App({
    target: document.body,
  });
}
export default app;
