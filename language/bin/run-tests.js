import assert from "assert";
import { opendir } from "fs/promises";
const dir = "gen/javascript/language/";

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

  console.log(`
${passes + failures} tests
${passes} passes
${failures} failures`);
  process.exit(failures ? 1 : 0);
}

main();