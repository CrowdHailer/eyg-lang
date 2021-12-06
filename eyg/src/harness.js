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
    function equal(a, b) {
      if (deepEqual(a, b)) {
        return {variant: "True", inner: []}
      } else {
        return {variant: "False", inner: []}
      }
    }
    // function zero$1() {
    //   return 0
    // }
    // function inc$1(x) {
    //   return x + 1
    // }
    function hole(message) {
      throw message
    }

    function debug(item) {
      console.log(item)
      return item
    }



    return eval(code);
  }

  export function identity(x) {
    return x
  }
