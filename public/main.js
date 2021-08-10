import {infer, failure_to_string} from "./gen/language/ast.js";
import * as Scope from "./gen/language/scope.js";
import {array} from "./helpers.js";

let raw, dirty, module;

const flask = new CodeFlask("#editor", { language: "js" });
flask.onUpdate((code) => {
  raw = code;
  dirty = true;
  compile();
});
flask.updateCode("varient(\"Foo\", [], list([\n\
  constructor(\"A\", []),\n\
  constructor(\"B\", []),\n\
  constructor(\"C\", [])]),\n\
  call(\n\
    fn(list(['x']), case_(var_(\"x\"), list([\n\
      clause('A', list([]), var_(\"x\")),\n\
      rest('other', var_(\"x\")),\n\
      clause('C', list([]), var_(\"x\")),\n\
    ]))),\n\
    list([call(var_(\"A\"), [])])\n\
  )\n\
)");

const prelude =
  "import {let_, binary, function$ as fn, var$ as var_, call, case_, clause, rest, varient, constructor} from 'http://localhost:5000/gen/language/ast/builder.js';\n\
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
  let scope = Scope.with_equal(Scope.new$())
  // console.log(array(scope.variables));
  let typed = infer(untyped, scope)
  if (typed.type == "Ok") {
    console.log("ok");
  } else {
    let message = failure_to_string(typed[0])
    console.log(message);
  }
}

window.compile = compile
console.log("Go!!")