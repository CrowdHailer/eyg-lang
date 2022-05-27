import * as T from "./eyg/typer/monotype.mjs";
import * as Eyg from "./eyg.mjs";
import * as Encode from "./eyg/ast/encode.mjs";
import * as Typer from "./eyg/typer.mjs";
import * as Gleam from "./gleam.mjs";
import * as Codegen from "./eyg/codegen/javascript.mjs";

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
    debug: function (item) {
      console.log(item);
      return item;
    },
    parse_int: function (x) {
      // TODO need to handle error case
      return parseInt(x);
    },
    add: function ([a, b]) {
      return a + b;
    },
    compare: function ([a, b]) {
      if (a == b) {
        return ({ Eq }) => Eq([]);
      } else if (a < b) {
        return ({ Lt }) => Lt([]);
      } else {
        return ({ Gt }) => Gt([]);
      }
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
      if (computed.isOk()) {
        return { OK: computed[0] };
      } else {
        return { Error: computed[0] };
      }
      window.eyg_source = everything;
    },
    source: function () {
      return window.eyg_source;
    },
  };
  foo(harness);
  // let T = Monotype
  // foo(T)
  // foo(Gleam)
  // foo(Option)
  return eval(code);
}
