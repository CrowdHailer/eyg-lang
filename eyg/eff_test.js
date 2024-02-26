import test from "node:test";
import assert from "node:assert/strict";

function Eff(label, value, k) {
  this.label = label;
  this.value = value;
  this.k = k;
}

let bind = (m, then) => {
  if (!(m instanceof Eff)) return then(m);
  let k = (x) => bind(m.k(x), then);
  return new Eff(m.label, m.value, k);
};

let perform = (label) => (value) => new Eff(label, value, (x) => x);

let handle = (label) => (handler) => (exec) => {
  return do_handle(label, handler, exec({}));
};

let do_handle = (label, handler, m) => {
  if (!(m instanceof Eff)) return m;
  let k = (x) => do_handle(label, handler, m.k(x));
  if (m.label == label) return handler(m.value)(k);
  return new Eff(m.label, m.value, k);
};

let run = (m, extrinsic) => {
  while (m instanceof Eff) {
    m = m.k(extrinsic[m.label](m.value));
  }
  return m;
};

let extrinsic = { Ask: (x) => 10, Log: (x) => console.log(x) };
let int_add = (x) => (y) => x + y;

test("foo", function (t) {
  let r = run(
    bind(perform("Ask")({}), (x) =>
      bind(
        handle("Ask")((v) => (k) => k(12))((_) =>
          bind(perform("Ask")({}), (y) => {
            console.log(x, y);
            return int_add(x)(y);
          })
        ),
        (t) => bind(perform("Log")({ t }), (_) => t)
      )
    ),
    extrinsic
  );

  // perform("Ask")({}).bind((x) =>
  //   handle("Ask")((v) => (k) => k(12))((_) =>
  //     perform("Ask")({}).bind((y) => {
  //       console.log(x, y);
  //       return int_add(x)(y);
  //     })
  //   ).bind((t) => perform("Log")({ t }).bind((_) => t))
  // );
  console.log(r);
  throw "bad";
});
