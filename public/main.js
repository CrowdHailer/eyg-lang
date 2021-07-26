import {infer} from "./gen/language/ast.js"
let raw, dirty, module;

const flask = new CodeFlask("#editor", { language: "js" });
flask.onUpdate((code) => {
  raw = code;
  dirty = true;
});
flask.updateCode("export function main() {\n\
    return call(\n\
        fn([[undefined, 'x'], []], var_(\"x\")),\n\
        [binary(), []]\n\
    )\n\
}");

const prelude =
  "import {let_, binary, function$ as fn, var$ as var_, call} from 'http://localhost:5000/gen/language/ast.js';\n";
async function compile() {
  return await import(
    URL.createObjectURL(
      new Blob([prelude, raw], { type: "text/javascript" })
    )
  );
}

async function getModule() {
  if (dirty) {
    module = await compile();
    dirty = false;
  }
  return module;
}
async function run(x) {
  let module = await getModule();
  let untyped = module.main(x);
  console.log(JSON.stringify(infer(untyped)));
}

window.run = run
console.log("Go!!")