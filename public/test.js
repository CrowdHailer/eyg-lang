import {infer, render} from "./gen/language/ast.js";
import * as Scope from "./gen/language/scope.js";
import {array} from "./helpers.js";

// const paths = ["http://localhost:5000/gen/my_lang_test.js"]
// for (const p of paths) {
//     let module = await import(p);
//     console.log(module);
//     for (const fnName of Object.keys(module)) {
//         if (fnName.endsWith("_test")) {
//             console.log(fnName);
//         }
//     }
// }

window.concatList = function (list, separator) {
    return array(list).join(separator)
}


let source = await import("http://localhost:5000/gen/my_lang/list.js");
let untyped = source.module();
let scope = source.types();
let typed = infer(untyped, scope);
// assumes OK
let [type_, tree, typer] = typed[0]
console.log(render([type_, tree]));

console.log("Testing", typed)
