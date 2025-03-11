import { Map, Stack } from "immutable";
import { describe, it } from "node:test";
import assert from "node:assert";
import { readFileSync } from "fs";
import { eval_, Tagged } from "./src/interpreter.mjs";
import { parse } from "@ipld/dag-json";

const testPath = "../../spec/evaluation/"

describe("specification tests", () => {
  [
    "core_suite.json",
    "builtins_suite.json",
    "effects_suite.json"
  ].forEach((testFile) => {
    let specs = parse(readFileSync(testPath + testFile, "utf8"))
    specs.forEach(({ name, source, effects = [], value, break: break_ }) => {
      // if (!name.includes("effects")) return
      it(name, () => {
        let state = eval_(source)
        effects.reduce((state, expected) => {
          assert.equal(expected.label, state.break.label)
          let lift = parseValue(expected.lift)
          if (lift.equals) {
            if (!lift.equals(state.break.lift)) {
              console.log(lift, state.break.lift)
              throw "not equal to lift"
            }
          } else {
            assert.deepStrictEqual(state.break.lift, lift);
          }
          let reply = parseValue(expected.reply)
          state.resume(reply)
          return state
        }, state)
        if (break_ !== undefined) {
          assert.deepStrictEqual(state.break, break_);
        } else {
          let expected = parseValue(value)
          if (expected.equals) {
            if (!expected.equals(state.control)) {
              console.log(expected, state.control)
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