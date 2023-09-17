import { run, do_run } from "../build/dev/javascript/eyg/platforms/browser.mjs";

// console.log(document.currentScript);
run();
window.EYG = { run: do_run };
