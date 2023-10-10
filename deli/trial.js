let isYielding = false;
let op = null;
let ks = null;
let w = [];

function handle(marker, handler, exec) {
  w = [{ marker, handler }, ...w];
  while (true) {
    value = exec();
    if (!isYielding) {
      return value;
    }
    // don't match if is not the same marker
    // New eyg src for code gen and quick test
    // fast interpreter for arduino -- tree shaking
    // binary -> generate binary code for arduino
    // compile away effects better for js/datalog implementation
    // hashes in native for hashconsing

    // generative tail call optimised -> how does this work with shallow
    const k = ((inner) => {
      return (value) => {
        inner.forEach((j) => {
          // I think we need to put the rest of the js on here
          value = j(value);
          if (isYielding) {
            return;
          }
        });
        if (isYielding) {
          return;
        }

        // is Yielding
        return value;
      };
    })([...ks]);
    const o = op;
    op = null;
    ks = null;
    isYielding = false;

    exec = () => o(k);
  }
  // TODO call this under
  return handle(marker, handler, () => o(k));
}

function perform(marker, value) {
  const handler = w[0].handler;
  op = (k) => {
    return handler(value, k);
  };
  ks = [];
  isYielding = true;
}

function run() {
  return handle(
    "ask",
    (v, k) => {
      let x = k(1);
      if (isYielding) {
        ks = [hj, ...ks];
        return;
      }
      return hj(x);
    },
    () => {
      const a = perform("ask", {});
      if (isYielding) {
        ks = [j1, ...ks];
        return;
      }
      return j1(a);
    }
  );
}

function hj(x) {
  return x + 10;
}

function j1(a) {
  const b = perform("ask", {});
  if (isYielding) {
    ks = [(b) => j2(a, b), ...ks];
    return;
  }
  return j2(a, b);
}

function j2(a, b) {
  return a + b;
}

// we don't return error we just panic for unhandled
function main() {
  let x = run();
  console.log("final", x);
  if (isYielding) {
    throw "should not be yielding";
    // print unhandled effect
  }
  //   cant I use try catch with a wrap fn alway pas j
  // shouldnot be yielding
}

console.log("start");
main();
console.log("end");
