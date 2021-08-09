import { opendir } from "fs/promises";
import F from "../gen/javascript/tmp/repro.js"
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

  console.log(`
${passes + failures} tests
${passes} passes
${failures} failures`);
  process.exit(failures ? 1 : 0);
}

main();