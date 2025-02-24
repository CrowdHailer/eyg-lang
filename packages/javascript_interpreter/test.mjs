import { Map, Stack } from "immutable";
import { describe, it } from "node:test";
import assert from "node:assert";
import { readFileSync } from "fs";
import { eval_, Tagged } from "./src/interpreter.mjs";

const testPath = "../../spec/evaluation/"

describe("specification tests", () => {
  [
    "core_suite.json",
    "builtins_suite.json"
  ].forEach((testFile) => {
    let specs = JSON.parse(readFileSync(testPath + testFile, "utf8"))
    specs.forEach(({ name, source, effects, value, break: break_ }) => {

      it(name, () => {
        let state = eval_(source)
        if (break_ !== undefined) {
          assert.deepStrictEqual(state.break, break_);
        } else {
          let expected = parseValue(value)
          if (expected.equals) {
            if (!expected.equals(state.control)) {
              throw "not equal"
            }
          } else {
            assert.deepStrictEqual(state.control, expected);
          }
        }
      });
    })
  })
});

function parseValue(raw) {
  let { binary, integer, string, list, record, tagged } = raw
  if (binary !== undefined) return binary
  if (integer !== undefined) return integer
  if (string !== undefined) return string
  if (list !== undefined) return Stack(list.map(parseValue))
  if (record !== undefined) return Map(Object.entries(record).map(([k, v]) => [k, parseValue(v)]))
  if (tagged !== undefined) return new Tagged(tagged.label, parseValue(tagged.value))
  console.log(raw)
  throw "how to parse"
}