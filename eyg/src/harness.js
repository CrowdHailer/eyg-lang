import * as Gleam from "./gleam.js"
import * as Option from "./gleam/option"
import * as Monotype from "./eyg/typer/monotype"

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
        return false
      }
    }
    return true;
  } else {
    return x === y;
  }
}

function isObject(object) {
  return object != null && typeof object === 'object';
}



// eyg list
function fromArray(array) {
  let empty = function ([Empty, _]) {
    return Empty([])
  }
  return array.reduceRight((xs, x) => {
    return function ([_, Head]) {
      return Head([x, xs])
    }
  }, empty)
}


let shown = false
function foo(x) {
  if (!shown) {
    console.log(x);
    shown = true
  }
}
//   incorperate helpers from codegen like variant() and unit()
export function run(code) {
  function equal([a, b]) {
    if (deepEqual(a, b)) {
      return ({ True: then }) => { return then([]) }
    } else {
      return ({ False: then }) => { return then([]) }
    }
  }


  // This is need or equal isn't evaled
  // console.log(equal)
  equal(["T", "T"])
  const harness = {
    split: function ([a, b]) {
      return fromArray(a.split(b))
    },
    debug: function (item) {
      console.log(item)
      return item
    },
    parse_int: function (x) {
      // TODO need to handle error case
      return parseInt(x)
    },
    add: function ([a, b]) {
      return a + b
    },
    compare: function ([a, b]) {
      if (a == b) {
        return ({ Eq }) => Eq([])
      } else if (a < b) {
        return ({ Lt }) => Lt([])
      } else {
        return ({ Gt }) => Gt([])
      }
    }
  }
  foo(harness)
  let T = Monotype
  foo(T)
  foo(Gleam)
  foo(Option)
  return eval(code);
}

export function identity(x) {
  return x
}

export function object(entries) {
  return Object.fromEntries(entries)
}

export function entries(object) {
  return Gleam.toList(Object.entries(object))
}

export function list(list) {
  return list.toArray()
}

export function from_array(array) {
  return Gleam.toList(array)
}

export function json_to_string(json) {
  return JSON.stringify(json, " ", 2);
}
