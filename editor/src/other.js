import * as Entry from "../../eyg/build/dev/javascript/eyg/dist/eyg/entry.mjs";
import * as Encode from "../../eyg/build/dev/javascript/eyg/dist/eyg/ast/encode.mjs";

// Roll up adds a default object that breaks matchings
import data from "../public/saved.json";
// This is not generic has because we have the server or maybe not. this is the arbitrary script pull
// let target = new URL(document.currentScript.src).hash.slice(1);
// console.log(target, Analysis);

(async function name() {
  const source = Encode.from_json(data);
  const initial = Entry.interpret_client(source, "counter");
  console.log(initial);
  const { default: next } = await import("../public/saved.json");
  console.log(Encode.from_json(data));
})();

// Started doing this because the code gen was troublesome, also in code gen we will nee to pull in the loader
// here we have can use the already existing gleam .run
