import { other } from "./foo.js";
import { run } from "../build/eyg/platforms/browser.mjs";

console.log(other());
console.log(run());
console.log(document.currentScript);
