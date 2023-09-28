import { run, do_run } from "./platforms/browser.mjs";

// console.log(document.currentScript);
run();
window.EYG = { run: do_run };
