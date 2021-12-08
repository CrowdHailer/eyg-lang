import * as Gleam from "./gleam.js"

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


//   incorperate helpers from codegen like variant() and unit()
export function run(code) {
  function equal([a, b]) {
    if (deepEqual(a, b)) {
      return ({ True: then }) => { return then([]) }
    } else {
      return ({ False: then }) => { return then([]) }
    }
  }
  // function zero$1() {
  //   return 0
  // }
  // function inc$1(x) {
  //   return x + 1
  // }

  function debug(item) {
    console.log(item)
    return item
  }

  // This is need or equal isn't evaled
  // console.log(equal)
  equal(["T", "T"])
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
