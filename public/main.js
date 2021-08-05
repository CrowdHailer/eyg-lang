import {infer} from "./gen/language/ast.js";
import * as Scope from "./gen/language/scope.js";
import {array} from "./helpers.js";
import {test} from "./gen/repro.js"

window.repro = test

let raw, dirty, module;

const flask = new CodeFlask("#editor", { language: "js" });
flask.onUpdate((code) => {
  raw = code;
  dirty = true;
  compile();
});
flask.updateCode("call(\n\
  fn(list(['x']), case_(var_(\"x\"), list([\n\
    clause('False', list([]), var_(\"x\")),\n\
    clause('True', list([]), var_(\"x\"))\n\
  ]))),\n\
  list([binary("abc")])\n\
)");

const prelude =
  "import {let_, binary, function$ as fn, var$ as var_, call, case_, clause, rest} from 'http://localhost:5000/gen/language/ast/builder.js';\n\
   import {list} from 'http://localhost:5000/helpers.js';\n";
async function readSource() {
  return await import(
    URL.createObjectURL(
      new Blob([prelude, "export function ast() {\n  return ", raw, "}"], { type: "text/javascript" })
    )
  );
}

async function getModule() {
  if (dirty) {
    module = await readSource();
    dirty = false;
  }
  return module;
}
async function compile() {
  let module = await getModule();
  let untyped = module.ast();
  let scope = Scope.with_foo(Scope.with_equal(Scope.new$()))
  // console.log(array(scope.variables));
  let typed = infer(untyped, scope)
  if (typed.type == "Ok") {
    console.log("ok");
  } else {
    let [failure, situation] = typed[0]
    console.log(failure, situation);
  }
}

window.compile = compile
console.log("Go!!")