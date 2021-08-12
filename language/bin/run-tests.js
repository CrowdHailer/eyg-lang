import assert from "assert";
import { opendir } from "fs/promises";
const dir = "gen/javascript/language/";
import fs from 'fs';

async function main() {
  console.log("Running tests...");

  let passes = 0;
  let failures = 0;

  for await (let entry of await opendir(dir)) {
    if (!entry.name.endsWith("_test.js")) continue;
    let path = "../" + dir + entry.name;
    process.stdout.write("\nlanguage/" + entry.name.slice(0, -3) + ":\n  ");
    let module = await import(path);

    for (let fnName of Object.keys(module)) {
      if (!fnName.endsWith("_test")) continue;
      try {
        module[fnName]();
        process.stdout.write("✨");
        passes++;
      } catch (error) {
        process.stdout.write(`❌ ${fnName}: ${error}\n  `);
        failures++;
      }
    }
  }

    //   Dumb duplication
  for await (let entry of await opendir(dir + "ast/")) {
    if (!entry.name.endsWith("_test.js")) continue;
    let path = "../" + dir + "ast/" + entry.name;
    process.stdout.write("\nlanguage/" + entry.name.slice(0, -3) + ":\n  ");
    let module = await import(path);

    for (let fnName of Object.keys(module)) {
      if (!fnName.endsWith("_test")) continue;
      try {
        module[fnName]();
        process.stdout.write("✨");
        passes++;
      } catch (error) {
        process.stdout.write(`❌ ${fnName}: ${error}\n  `);
        failures++;
      }
    }
  }

  await (async () => {
    const module = await import("../gen/javascript/my_lang_test.js")
    const {Cons, Nil, reverse, map} = eval(module.list_test());
    let l1 = Cons(1, Cons(2, Nil()))
    let l2 = Cons(2, Cons(1, Nil()))
    assert.deepStrictEqual(reverse(l1), l2)
  })()

  process.stdout.write("\n\n## EYG\n\n");

  await (async () => {
    const source = await import("../gen/javascript/eyg/module.js")
    let should = {
      equal$1: (a, b) => {
        if ($deepEqual(a, b)) {
          return null
        } else {
          console.log(a, " VS ", b)
          throw "values are not equal"
        }
      },
      not_equal$1: (a, b) => {
        if ($deepEqual(a, b)) {
          console.log(a, " AND ", b)
          throw "values are equal"
        } else {
          return null
        }
      }
    }
    function equal$1(a, b) {
      if ($deepEqual(a, b)) {
        return {type: "True"}
      } else {
        return {type: "False"}
      }  
    }
    function zero$1() {
      return 0
    }
    function inc$1(x) {
      return x + 1
    }
    function unimplemented$1(message) {
      throw "UNIMPLEMENTED: " + message
    }


    // TODO put console output in an array.
    const code = source.compiled()
    fs.writeFileSync('./tmp/eyg.js', code)
    const module = eval(code);
    for (let fnName of Object.keys(module)) {
      if (!fnName.endsWith("_test")) continue;
      try {
        let result = module[fnName]();
        if (result) {
          console.log(JSON.stringify(result))
        }
        process.stdout.write("✨");
        passes++;
      } catch (error) {
        process.stdout.write(`❌ ${fnName}: ${error}\n  `);
        failures++;
      }
    }
  })()

  console.log(`
${passes + failures} tests
${passes} passes
${failures} failures`);
  process.exit(failures ? 1 : 0);
}

main();

function $deepEqual(x, y) {
  if ($isObject(x) && $isObject(y)) {
    const kx = Object.keys(x);
    const ky = Object.keys(x);
    if (kx.length != ky.length) {
      return false;
    }
    for (const k of kx) {
      const a = x[k];
      const b = y[k];
      if (!$deepEqual(a, b)) {
        return false
      }
    }
    return true;
  } else {
    return x === y;
  }
}
function $isObject(object) {
  return object != null && typeof object === 'object';
}