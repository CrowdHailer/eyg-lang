import { Map, Stack } from "immutable";
import { describe, it } from "node:test";
import assert from "node:assert";
import { readFileSync } from "fs";
import { eval_, Tagged } from "./src/interpreter.mjs";

const testPath = "../../ir/tests/"

describe("specification tests", () => {
  [
    { source: "integer.json", want: 42 },
    { source: "ignored_argument.json", want: 100 },
    { source: "ordered_argument.json", want: 2 },
    { source: "single_let.json", want: 10 },

    { source: "vacant.json", raise: "not implemented" },
    { source: "string.json", want: "g'day" },
    { source: "empty_list.json", want: Stack() },
    { source: "list.json", want: Stack([101, 102]) },

    { source: "match.json", want: "something terrible" },
    { source: "match_otherwise.json", want: new Tagged("Error", "something interesting") },

    { source: "integer_subtract.json", want: 4 },

  ].forEach(({ source, want, raise }) => {
    it(source, () => {
      let d = JSON.parse(readFileSync(testPath + source, "utf8"))
      let state = eval_(d)
      if (raise) {
        assert.deepStrictEqual(state.break.message, raise);
      } else {
        assert.deepStrictEqual(state.control, want);
      }
    });
  })
});



const goTestPath = "../../mulch/test/"

describe("specification tests", () => {
  [
    { source: "environment_capture.json", want: 1 },
    { source: "nested_apply.json", want: 4 },
    { source: "nested_let.json", want: 1 },
    { source: "param_in_env.json", want: 2 },
    { source: "records/record_select.json", want: "hey" },
    { source: "effects/continue_exec.json", want: new Tagged("Tagged", 1) },
    { source: "effects/evaluate_exec_function.json", want: new Tagged("Ok", 5) },
    { source: "effects/evaluate_handle.json", want: new Tagged("Error", "bang!!") },
    { source: "effects/multiple_perform.json", want: Stack([1, 2]) },
    { source: "effects/multiple_resume.json", want: Stack([2, 3]) },

  ].forEach(({ source, want }) => {
    it(source, () => {
      let d = JSON.parse(readFileSync(goTestPath + source, "utf8"))
      let state = eval_(d)
      assert.deepStrictEqual(state.control, want);
    });
  })
});

