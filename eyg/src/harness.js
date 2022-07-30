import * as T from "./eyg/typer/monotype.mjs";
import * as Eyg from "./eyg.mjs";

console.log(T);
function deepEqual(x, y) {
  if (isObject(x) && isObject(y)) {
    const kx = Object.keys(x);
    const ky = Object.keys(x);
    if (kx.length != ky.length) {
      return false;
    }
    for (const k of kx) {
      const a = x[k];
      const b = y[k];
      if (!deepEqual(a, b)) {
        return false;
      }
    }
    return true;
  } else {
    return x === y;
  }
}

function isObject(object) {
  return object != null && typeof object === "object";
}

// eyg list
function fromArray(array) {
  let empty = function ([Empty, _]) {
    return Empty([]);
  };
  return array.reduceRight((xs, x) => {
    return function ([_, Head]) {
      return Head([x, xs]);
    };
  }, empty);
}

let shown = false;
function foo(x) {
  if (!shown) {
    console.log(x);
    shown = true;
  }
}
//   incorperate helpers from codegen like variant() and unit()
export function run(code) {
  function equal([a, b]) {
    if (deepEqual(a, b)) {
      return { True: [] };
    } else {
      return { False: [] };
    }
  }

  // This is need or equal isn't evaled
  // console.log(equal)
  equal(["T", "T"]);
  const harness = {
    split: function ([a, b]) {
      return fromArray(a.split(b));
    },
    concat: function ([a, b]) {
      return a + b;
    },
    debug: function (item) {
      console.log(item);
      return item;
    },
    compile: function ([source, constraint_literal]) {
      let constraint = eval(constraint_literal);

      // There is a recursive compile stack if we have a program with a Loader that accesses all the source
      // Putting this to empty prevents them running forever
      // A program must not use the same loader in the code that is loaded
      // Potentially making a lazy provider infrastructure would fix this
      let empty = '{"node": "Hole"}';
      let everything = window.eyg_source;
      window.eyg_source = empty;
      // In Gleam format
      let computed = Eyg.provider(source, constraint);
      let result;
      if (computed.isOk()) {
        result = { OK: computed[0] };
      } else {
        result = { Error: computed[0] };
      }
      window.eyg_source = everything;
      return result;
    },
    source: function () {
      return window.eyg_source;
    },
    fetch: function (url) {
      return function (cont) {
        fetch(url).then((resp) => resp.text().then((body) => cont(body)));
        return [];
      };
    },
    deserialize: function (raw) {
      return JSON.parse(raw);
    },
    key: function ([object, key]) {
      return object[key];
    },
    spawn: function (params) {
      // console.log("Should this be in compiled code", params);
      return function (continuation) {
        // console.log("spawned", params);
        return continuation({ Address: 1 });
      };
    },
  };
  foo(harness);
  const int = {
    parse: function (x) {
      const maybeInt = parseInt(x);
      // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/isNaN#confusing_special-case_behavior
      // leverages the unique never-equal-to-itself characteristic of NaN
      if (maybeInt != maybeInt) {
        return { Error: [] };
      } else {
        return { OK: maybeInt };
      }
    },
    to_string: function (i) {
      return i.toString();
    },
    add: function ([a, b]) {
      return a + b;
    },
    multiply: function ([a, b]) {
      return a * b;
    },
    negate: function (a) {
      return -1 * b;
    },
    compare: function ([a, b]) {
      if (a == b) {
        return { Eq: [] };
      } else if (a < b) {
        return { Lt: [] };
      } else {
        return { Gt: [] };
      }
    },
    // This is because I don't have a parse assertion
    // perhaps constant folding, not assert is the way forward here.
    zero: 0,
    one: 1,
    two: 2,
  };
  foo(int);

  // let T = Monotype
  // foo(T)
  // foo(Gleam)
  // foo(Option)
  return eval(code);
}
