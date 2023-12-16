(function () {
  'use strict';

  class CustomType {
    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      let field = (label) => {
        let value = inspect$2(this[label]);
        return isNaN(parseInt(label)) ? `${label}: ${value}` : value;
      };
      let props = Object.keys(this).map(field).join(", ");
      return props ? `${this.constructor.name}(${props})` : this.constructor.name;
    }

    withFields(fields) {
      let properties = Object.keys(this).map((label) =>
        label in fields ? fields[label] : this[label]
      );
      return new this.constructor(...properties);
    }
  }

  class List {
    static fromArray(array, tail) {
      let t = tail || new Empty();
      return array.reduceRight((xs, x) => new NonEmpty(x, xs), t);
    }

    [Symbol.iterator]() {
      return new ListIterator(this);
    }

    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      return `[${this.toArray().map(inspect$2).join(", ")}]`;
    }

    toArray() {
      return [...this];
    }

    atLeastLength(desired) {
      for (let _ of this) {
        if (desired <= 0) return true;
        desired--;
      }
      return desired <= 0;
    }

    hasLength(desired) {
      for (let _ of this) {
        if (desired <= 0) return false;
        desired--;
      }
      return desired === 0;
    }

    countLength() {
      let length = 0;
      for (let _ of this) length++;
      return length;
    }
  }

  function toList(elements, tail) {
    return List.fromArray(elements, tail);
  }

  class ListIterator {
    #current;

    constructor(current) {
      this.#current = current;
    }

    next() {
      if (this.#current instanceof Empty) {
        return { done: true };
      } else {
        let { head, tail } = this.#current;
        this.#current = tail;
        return { value: head, done: false };
      }
    }
  }

  class Empty extends List {}

  class NonEmpty extends List {
    constructor(head, tail) {
      super();
      this.head = head;
      this.tail = tail;
    }
  }

  class BitArray {
    constructor(buffer) {
      if (!(buffer instanceof Uint8Array)) {
        throw "BitArray can only be constructed from a Uint8Array";
      }
      this.buffer = buffer;
    }

    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      return `<<${Array.from(this.buffer).join(", ")}>>`;
    }

    get length() {
      return this.buffer.length;
    }

    byteAt(index) {
      return this.buffer[index];
    }

    floatAt(index) {
      return byteArrayToFloat(this.buffer.slice(index, index + 8));
    }

    intFromSlice(start, end) {
      return byteArrayToInt(this.buffer.slice(start, end));
    }

    binaryFromSlice(start, end) {
      return new BitArray(this.buffer.slice(start, end));
    }

    sliceAfter(index) {
      return new BitArray(this.buffer.slice(index));
    }
  }

  class UtfCodepoint {
    constructor(value) {
      this.value = value;
    }

    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      return `//utfcodepoint(${String.fromCodePoint(this.value)})`;
    }
  }

  function byteArrayToInt(byteArray) {
    byteArray = byteArray.reverse();
    let value = 0;
    for (let i = byteArray.length - 1; i >= 0; i--) {
      value = value * 256 + byteArray[i];
    }
    return value;
  }

  function byteArrayToFloat(byteArray) {
    return new Float64Array(byteArray.reverse().buffer)[0];
  }

  class Result extends CustomType {
    static isResult(data) {
      return data instanceof Result;
    }
  }

  class Ok extends Result {
    constructor(value) {
      super();
      this[0] = value;
    }

    isOk() {
      return true;
    }
  }

  class Error extends Result {
    constructor(detail) {
      super();
      this[0] = detail;
    }

    isOk() {
      return false;
    }
  }

  function inspect$2(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$2).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$2).join(", ")}))`;
    if (v instanceof RegExp) return `//js(${v})`;
    if (v instanceof Date) return `//js(Date("${v.toISOString()}"))`;
    if (v instanceof Function) {
      let args = [];
      for (let i of Array(v.length).keys())
        args.push(String.fromCharCode(i + 97));
      return `//fn(${args.join(", ")}) { ... }`;
    }
    try {
      return v.inspect();
    } catch (_) {
      return inspectObject$1(v);
    }
  }

  function inspectObject$1(v) {
    let [keys, get] = getters(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$2(k)}: ${inspect$2(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function isEqual(x, y) {
    let values = [x, y];

    while (values.length) {
      let a = values.pop();
      let b = values.pop();
      if (a === b) continue;

      if (!isObject(a) || !isObject(b)) return false;
      let unequal =
        !structurallyCompatibleObjects(a, b) ||
        unequalDates(a, b) ||
        unequalBuffers(a, b) ||
        unequalArrays(a, b) ||
        unequalMaps(a, b) ||
        unequalSets(a, b);
      if (unequal) return false;

      const proto = Object.getPrototypeOf(a);
      if (proto !== null && typeof proto.equals === "function") {
        try {
          if (a.equals(b)) continue;
          else return false;
        } catch {}
      }

      let [keys, get] = getters(a);
      for (let k of keys(a)) {
        values.push(get(a, k), get(b, k));
      }
    }

    return true;
  }

  function getters(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  function unequalDates(a, b) {
    return a instanceof Date && (a > b || a < b);
  }

  function unequalBuffers(a, b) {
    return (
      a.buffer instanceof ArrayBuffer &&
      a.BYTES_PER_ELEMENT &&
      !(a.byteLength === b.byteLength && a.every((n, i) => n === b[i]))
    );
  }

  function unequalArrays(a, b) {
    return Array.isArray(a) && a.length !== b.length;
  }

  function unequalMaps(a, b) {
    return a instanceof Map && a.size !== b.size;
  }

  function unequalSets(a, b) {
    return (
      a instanceof Set && (a.size != b.size || [...a].some((e) => !b.has(e)))
    );
  }

  function isObject(a) {
    return typeof a === "object" && a !== null;
  }

  function structurallyCompatibleObjects(a, b) {
    if (typeof a !== "object" && typeof b !== "object" && (!a || !b))
      return false;

    let nonstructural = [Promise, WeakSet, WeakMap, Function];
    if (nonstructural.some((c) => a instanceof c)) return false;

    return a.constructor === b.constructor;
  }

  function makeError(variant, module, line, fn, message, extra) {
    let error = new globalThis.Error(message);
    error.gleam_error = variant;
    error.module = module;
    error.line = line;
    error.fn = fn;
    for (let k in extra) error[k] = extra[k];
    return error;
  }

  class Some extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class None extends CustomType {}

  function to_result(option, e) {
    if (option instanceof Some) {
      let a = option[0];
      return new Ok(a);
    } else {
      return new Error(e);
    }
  }

  function from_result(result) {
    if (result.isOk()) {
      let a = result[0];
      return new Some(a);
    } else {
      return new None();
    }
  }

  function to_string$2(x) {
    return to_string(x);
  }

  function do_length_acc(loop$list, loop$count) {
    while (true) {
      let list = loop$list;
      let count = loop$count;
      if (list.atLeastLength(1)) {
        let list$1 = list.tail;
        loop$list = list$1;
        loop$count = count + 1;
      } else {
        return count;
      }
    }
  }

  function do_length(list) {
    return do_length_acc(list, 0);
  }

  function length(list) {
    return do_length(list);
  }

  function do_reverse_acc(loop$remaining, loop$accumulator) {
    while (true) {
      let remaining = loop$remaining;
      let accumulator = loop$accumulator;
      if (remaining.hasLength(0)) {
        return accumulator;
      } else if (remaining.atLeastLength(1)) {
        let item = remaining.head;
        let rest$1 = remaining.tail;
        loop$remaining = rest$1;
        loop$accumulator = toList([item], accumulator);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          124,
          "do_reverse_acc",
          "No case clause matched",
          { values: [remaining] }
        )
      }
    }
  }

  function do_reverse(list) {
    return do_reverse_acc(list, toList([]));
  }

  function reverse(xs) {
    return do_reverse(xs);
  }

  function do_filter_map(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let new_acc = (() => {
          let $ = fun(x);
          if ($.isOk()) {
            let x$1 = $[0];
            return toList([x$1], acc);
          } else if (!$.isOk()) {
            return acc;
          } else {
            throw makeError(
              "case_no_match",
              "gleam/list",
              332,
              "do_filter_map",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        loop$list = xs;
        loop$fun = fun;
        loop$acc = new_acc;
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          329,
          "do_filter_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function filter_map(list, fun) {
    return do_filter_map(list, fun, toList([]));
  }

  function do_map(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        loop$list = xs;
        loop$fun = fun;
        loop$acc = toList([fun(x)], acc);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          361,
          "do_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function map$1(list, fun) {
    return do_map(list, fun, toList([]));
  }

  function do_index_map(loop$list, loop$fun, loop$index, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let index = loop$index;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let acc$1 = toList([fun(index, x)], acc);
        loop$list = xs;
        loop$fun = fun;
        loop$index = index + 1;
        loop$acc = acc$1;
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          449,
          "do_index_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function index_map(list, fun) {
    return do_index_map(list, fun, 0, toList([]));
  }

  function do_try_map(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return new Ok(reverse(acc));
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let $ = fun(x);
        if ($.isOk()) {
          let y = $[0];
          loop$list = xs;
          loop$fun = fun;
          loop$acc = toList([y], acc);
        } else if (!$.isOk()) {
          let error = $[0];
          return new Error(error);
        } else {
          throw makeError(
            "case_no_match",
            "gleam/list",
            483,
            "do_try_map",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          480,
          "do_try_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function try_map(list, fun) {
    return do_try_map(list, fun, toList([]));
  }

  function do_append_acc(loop$first, loop$second) {
    while (true) {
      let first = loop$first;
      let second = loop$second;
      if (first.hasLength(0)) {
        return second;
      } else if (first.atLeastLength(1)) {
        let item = first.head;
        let rest$1 = first.tail;
        loop$first = rest$1;
        loop$second = toList([item], second);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          635,
          "do_append_acc",
          "No case clause matched",
          { values: [first] }
        )
      }
    }
  }

  function do_append(first, second) {
    return do_append_acc(reverse(first), second);
  }

  function append(first, second) {
    return do_append(first, second);
  }

  function reverse_and_prepend(loop$prefix, loop$suffix) {
    while (true) {
      let prefix = loop$prefix;
      let suffix = loop$suffix;
      if (prefix.hasLength(0)) {
        return suffix;
      } else if (prefix.atLeastLength(1)) {
        let first$1 = prefix.head;
        let rest$1 = prefix.tail;
        loop$prefix = rest$1;
        loop$suffix = toList([first$1], suffix);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          654,
          "reverse_and_prepend",
          "No case clause matched",
          { values: [prefix] }
        )
      }
    }
  }

  function do_concat(loop$lists, loop$acc) {
    while (true) {
      let lists = loop$lists;
      let acc = loop$acc;
      if (lists.hasLength(0)) {
        return reverse(acc);
      } else if (lists.atLeastLength(1)) {
        let list = lists.head;
        let further_lists = lists.tail;
        loop$lists = further_lists;
        loop$acc = reverse_and_prepend(list, acc);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          661,
          "do_concat",
          "No case clause matched",
          { values: [lists] }
        )
      }
    }
  }

  function concat$2(lists) {
    return do_concat(lists, toList([]));
  }

  function flatten(lists) {
    return do_concat(lists, toList([]));
  }

  function fold(loop$list, loop$initial, loop$fun) {
    while (true) {
      let list = loop$list;
      let initial = loop$initial;
      let fun = loop$fun;
      if (list.hasLength(0)) {
        return initial;
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let rest$1 = list.tail;
        loop$list = rest$1;
        loop$initial = fun(initial, x);
        loop$fun = fun;
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          726,
          "fold",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function map(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return new Ok(fun(x));
    } else if (!result.isOk()) {
      let e = result[0];
      return new Error(e);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        67,
        "map",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function map_error(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return new Ok(x);
    } else if (!result.isOk()) {
      let error = result[0];
      return new Error(fun(error));
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        95,
        "map_error",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function try$(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return fun(x);
    } else if (!result.isOk()) {
      let e = result[0];
      return new Error(e);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        162,
        "try",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function then$(result, fun) {
    return try$(result, fun);
  }

  function unwrap(result, default$) {
    if (result.isOk()) {
      let v = result[0];
      return v;
    } else if (!result.isOk()) {
      return default$;
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        193,
        "unwrap",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function from_strings(strings) {
    return concat$1(strings);
  }

  function to_string$1(builder) {
    return identity$1(builder);
  }

  class DecodeError extends CustomType {
    constructor(expected, found, path) {
      super();
      this.expected = expected;
      this.found = found;
      this.path = path;
    }
  }

  function from$1(a) {
    return identity$1(a);
  }

  function string$2(data) {
    return decode_string(data);
  }

  function classify(data) {
    return classify_dynamic(data);
  }

  function int$2(data) {
    return decode_int(data);
  }

  function bool$2(data) {
    return decode_bool(data);
  }

  function shallow_list(value) {
    return decode_list(value);
  }

  function any(decoders) {
    return (data) => {
      if (decoders.hasLength(0)) {
        return new Error(
          toList([new DecodeError("another type", classify(data), toList([]))]),
        );
      } else if (decoders.atLeastLength(1)) {
        let decoder = decoders.head;
        let decoders$1 = decoders.tail;
        let $ = decoder(data);
        if ($.isOk()) {
          let decoded = $[0];
          return new Ok(decoded);
        } else if (!$.isOk()) {
          return any(decoders$1)(data);
        } else {
          throw makeError(
            "case_no_match",
            "gleam/dynamic",
            1026,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "gleam/dynamic",
          1019,
          "",
          "No case clause matched",
          { values: [decoders] }
        )
      }
    };
  }

  function all_errors(result) {
    if (result.isOk()) {
      return toList([]);
    } else if (!result.isOk()) {
      let errors = result[0];
      return errors;
    } else {
      throw makeError(
        "case_no_match",
        "gleam/dynamic",
        1504,
        "all_errors",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function decode1(constructor, t1) {
    return (value) => {
      let $ = t1(value);
      if ($.isOk()) {
        let a = $[0];
        return new Ok(constructor(a));
      } else {
        let a = $;
        return new Error(all_errors(a));
      }
    };
  }

  function push_path(error, name) {
    let name$1 = from$1(name);
    let decoder = any(
      toList([string$2, (x) => { return map(int$2(x), to_string$2); }]),
    );
    let name$2 = (() => {
      let $ = decoder(name$1);
      if ($.isOk()) {
        let name$2 = $[0];
        return name$2;
      } else if (!$.isOk()) {
        let _pipe = toList(["<", classify(name$1), ">"]);
        let _pipe$1 = from_strings(_pipe);
        return to_string$1(_pipe$1);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/dynamic",
          598,
          "push_path",
          "No case clause matched",
          { values: [$] }
        )
      }
    })();
    return error.withFields({ path: toList([name$2], error.path) });
  }

  function list$1(decoder_type) {
    return (dynamic) => {
      return try$(
        shallow_list(dynamic),
        (list) => {
          let _pipe = list;
          let _pipe$1 = try_map(_pipe, decoder_type);
          return map_errors(
            _pipe$1,
            (_capture) => { return push_path(_capture, "*"); },
          );
        },
      );
    };
  }

  function map_errors(result, f) {
    return map_error(
      result,
      (_capture) => { return map$1(_capture, f); },
    );
  }

  function field(name, inner_type) {
    return (value) => {
      let missing_field_error = new DecodeError("field", "nothing", toList([]));
      return try$(
        decode_field(value, name),
        (maybe_inner) => {
          let _pipe = maybe_inner;
          let _pipe$1 = to_result(_pipe, toList([missing_field_error]));
          let _pipe$2 = try$(_pipe$1, inner_type);
          return map_errors(
            _pipe$2,
            (_capture) => { return push_path(_capture, name); },
          );
        },
      );
    };
  }

  function tuple_errors(result, name) {
    if (result.isOk()) {
      return toList([]);
    } else if (!result.isOk()) {
      let errors = result[0];
      return map$1(
        errors,
        (_capture) => { return push_path(_capture, name); },
      );
    } else {
      throw makeError(
        "case_no_match",
        "gleam/dynamic",
        589,
        "tuple_errors",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function tuple2$1(decode1, decode2) {
    return (value) => {
      return try$(
        decode_tuple2(value),
        (_use0) => {
          let a = _use0[0];
          let b = _use0[1];
          let $ = decode1(a);
          let $1 = decode2(b);
          if ($.isOk() && $1.isOk()) {
            let a$1 = $[0];
            let b$1 = $1[0];
            return new Ok([a$1, b$1]);
          } else {
            let a$1 = $;
            let b$1 = $1;
            let _pipe = tuple_errors(a$1, "0");
            let _pipe$1 = append(_pipe, tuple_errors(b$1, "1"));
            return new Error(_pipe$1);
          }
        },
      );
    };
  }

  function tuple3$1(decode1, decode2, decode3) {
    return (value) => {
      return try$(
        decode_tuple3(value),
        (_use0) => {
          let a = _use0[0];
          let b = _use0[1];
          let c = _use0[2];
          let $ = decode1(a);
          let $1 = decode2(b);
          let $2 = decode3(c);
          if ($.isOk() && $1.isOk() && $2.isOk()) {
            let a$1 = $[0];
            let b$1 = $1[0];
            let c$1 = $2[0];
            return new Ok([a$1, b$1, c$1]);
          } else {
            let a$1 = $;
            let b$1 = $1;
            let c$1 = $2;
            let _pipe = tuple_errors(a$1, "0");
            let _pipe$1 = append(_pipe, tuple_errors(b$1, "1"));
            let _pipe$2 = append(_pipe$1, tuple_errors(c$1, "2"));
            return new Error(_pipe$2);
          }
        },
      );
    };
  }

  function decode2(constructor, t1, t2) {
    return (value) => {
      let $ = t1(value);
      let $1 = t2(value);
      if ($.isOk() && $1.isOk()) {
        let a = $[0];
        let b = $1[0];
        return new Ok(constructor(a, b));
      } else {
        let a = $;
        let b = $1;
        return new Error(concat$2(toList([all_errors(a), all_errors(b)])));
      }
    };
  }

  /**
   * This file uses jsdoc to annotate types.
   * These types can be checked using the typescript compiler with "checkjs" option.
   */

  const referenceMap = new WeakMap();
  const tempDataView = new DataView(new ArrayBuffer(8));
  let referenceUID = 0;
  /**
   * hash the object by reference using a weak map and incrementing uid
   * @param {any} o
   * @returns {number}
   */
  function hashByReference(o) {
    const known = referenceMap.get(o);
    if (known !== undefined) {
      return known;
    }
    const hash = referenceUID++;
    if (referenceUID === 0x7fffffff) {
      referenceUID = 0;
    }
    referenceMap.set(o, hash);
    return hash;
  }
  /**
   * merge two hashes in an order sensitive way
   * @param {number} a
   * @param {number} b
   * @returns {number}
   */
  function hashMerge(a, b) {
    return (a ^ (b + 0x9e3779b9 + (a << 6) + (a >> 2))) | 0;
  }
  /**
   * standard string hash popularised by java
   * @param {string} s
   * @returns {number}
   */
  function hashString(s) {
    let hash = 0;
    const len = s.length;
    for (let i = 0; i < len; i++) {
      hash = (Math.imul(31, hash) + s.charCodeAt(i)) | 0;
    }
    return hash;
  }
  /**
   * hash a number by converting to two integers and do some jumbling
   * @param {number} n
   * @returns {number}
   */
  function hashNumber(n) {
    tempDataView.setFloat64(0, n);
    const i = tempDataView.getInt32(0);
    const j = tempDataView.getInt32(4);
    return Math.imul(0x45d9f3b, (i >> 16) ^ i) ^ j;
  }
  /**
   * hash a BigInt by converting it to a string and hashing that
   * @param {BigInt} n
   * @returns {number}
   */
  function hashBigInt(n) {
    return hashString(n.toString());
  }
  /**
   * hash any js object
   * @param {any} o
   * @returns {number}
   */
  function hashObject(o) {
    const proto = Object.getPrototypeOf(o);
    if (proto !== null && typeof proto.hashCode === "function") {
      try {
        const code = o.hashCode(o);
        if (typeof code === "number") {
          return code;
        }
      } catch {}
    }
    if (o instanceof Promise || o instanceof WeakSet || o instanceof WeakMap) {
      return hashByReference(o);
    }
    if (o instanceof Date) {
      return hashNumber(o.getTime());
    }
    let h = 0;
    if (o instanceof ArrayBuffer) {
      o = new Uint8Array(o);
    }
    if (Array.isArray(o) || o instanceof Uint8Array) {
      for (let i = 0; i < o.length; i++) {
        h = (Math.imul(31, h) + getHash(o[i])) | 0;
      }
    } else if (o instanceof Set) {
      o.forEach((v) => {
        h = (h + getHash(v)) | 0;
      });
    } else if (o instanceof Map) {
      o.forEach((v, k) => {
        h = (h + hashMerge(getHash(v), getHash(k))) | 0;
      });
    } else {
      const keys = Object.keys(o);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        const v = o[k];
        h = (h + hashMerge(getHash(v), hashString(k))) | 0;
      }
    }
    return h;
  }
  /**
   * hash any js value
   * @param {any} u
   * @returns {number}
   */
  function getHash(u) {
    if (u === null) return 0x42108422;
    if (u === undefined) return 0x42108423;
    if (u === true) return 0x42108421;
    if (u === false) return 0x42108420;
    switch (typeof u) {
      case "number":
        return hashNumber(u);
      case "string":
        return hashString(u);
      case "bigint":
        return hashBigInt(u);
      case "object":
        return hashObject(u);
      case "symbol":
        return hashByReference(u);
      case "function":
        return hashByReference(u);
      default:
        return 0; // should be unreachable
    }
  }
  /**
   * @template K,V
   * @typedef {ArrayNode<K,V> | IndexNode<K,V> | CollisionNode<K,V>} Node
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof ENTRY, k: K, v: V }} Entry
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof ARRAY_NODE, size: number, array: (undefined | Entry<K,V> | Node<K,V>)[] }} ArrayNode
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof INDEX_NODE, bitmap: number, array: (Entry<K,V> | Node<K,V>)[] }} IndexNode
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof COLLISION_NODE, hash: number, array: Entry<K, V>[] }} CollisionNode
   */
  /**
   * @typedef {{ val: boolean }} Flag
   */
  const SHIFT = 5; // number of bits you need to shift by to get the next bucket
  const BUCKET_SIZE = Math.pow(2, SHIFT);
  const MASK = BUCKET_SIZE - 1; // used to zero out all bits not in the bucket
  const MAX_INDEX_NODE = BUCKET_SIZE / 2; // when does index node grow into array node
  const MIN_ARRAY_NODE = BUCKET_SIZE / 4; // when does array node shrink to index node
  const ENTRY = 0;
  const ARRAY_NODE = 1;
  const INDEX_NODE = 2;
  const COLLISION_NODE = 3;
  /** @type {IndexNode<any,any>} */
  const EMPTY = {
    type: INDEX_NODE,
    bitmap: 0,
    array: [],
  };
  /**
   * Mask the hash to get only the bucket corresponding to shift
   * @param {number} hash
   * @param {number} shift
   * @returns {number}
   */
  function mask(hash, shift) {
    return (hash >>> shift) & MASK;
  }
  /**
   * Set only the Nth bit where N is the masked hash
   * @param {number} hash
   * @param {number} shift
   * @returns {number}
   */
  function bitpos(hash, shift) {
    return 1 << mask(hash, shift);
  }
  /**
   * Count the number of 1 bits in a number
   * @param {number} x
   * @returns {number}
   */
  function bitcount(x) {
    x -= (x >> 1) & 0x55555555;
    x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
    x = (x + (x >> 4)) & 0x0f0f0f0f;
    x += x >> 8;
    x += x >> 16;
    return x & 0x7f;
  }
  /**
   * Calculate the array index of an item in a bitmap index node
   * @param {number} bitmap
   * @param {number} bit
   * @returns {number}
   */
  function index$1(bitmap, bit) {
    return bitcount(bitmap & (bit - 1));
  }
  /**
   * Efficiently copy an array and set one value at an index
   * @template T
   * @param {T[]} arr
   * @param {number} at
   * @param {T} val
   * @returns {T[]}
   */
  function cloneAndSet(arr, at, val) {
    const len = arr.length;
    const out = new Array(len);
    for (let i = 0; i < len; ++i) {
      out[i] = arr[i];
    }
    out[at] = val;
    return out;
  }
  /**
   * Efficiently copy an array and insert one value at an index
   * @template T
   * @param {T[]} arr
   * @param {number} at
   * @param {T} val
   * @returns {T[]}
   */
  function spliceIn(arr, at, val) {
    const len = arr.length;
    const out = new Array(len + 1);
    let i = 0;
    let g = 0;
    while (i < at) {
      out[g++] = arr[i++];
    }
    out[g++] = val;
    while (i < len) {
      out[g++] = arr[i++];
    }
    return out;
  }
  /**
   * Efficiently copy an array and remove one value at an index
   * @template T
   * @param {T[]} arr
   * @param {number} at
   * @returns {T[]}
   */
  function spliceOut(arr, at) {
    const len = arr.length;
    const out = new Array(len - 1);
    let i = 0;
    let g = 0;
    while (i < at) {
      out[g++] = arr[i++];
    }
    ++i;
    while (i < len) {
      out[g++] = arr[i++];
    }
    return out;
  }
  /**
   * Create a new node containing two entries
   * @template K,V
   * @param {number} shift
   * @param {K} key1
   * @param {V} val1
   * @param {number} key2hash
   * @param {K} key2
   * @param {V} val2
   * @returns {Node<K,V>}
   */
  function createNode(shift, key1, val1, key2hash, key2, val2) {
    const key1hash = getHash(key1);
    if (key1hash === key2hash) {
      return {
        type: COLLISION_NODE,
        hash: key1hash,
        array: [
          { type: ENTRY, k: key1, v: val1 },
          { type: ENTRY, k: key2, v: val2 },
        ],
      };
    }
    const addedLeaf = { val: false };
    return assoc(
      assocIndex(EMPTY, shift, key1hash, key1, val1, addedLeaf),
      shift,
      key2hash,
      key2,
      val2,
      addedLeaf
    );
  }
  /**
   * @template T,K,V
   * @callback AssocFunction
   * @param {T} root
   * @param {number} shift
   * @param {number} hash
   * @param {K} key
   * @param {V} val
   * @param {Flag} addedLeaf
   * @returns {Node<K,V>}
   */
  /**
   * Associate a node with a new entry, creating a new node
   * @template T,K,V
   * @type {AssocFunction<Node<K,V>,K,V>}
   */
  function assoc(root, shift, hash, key, val, addedLeaf) {
    switch (root.type) {
      case ARRAY_NODE:
        return assocArray(root, shift, hash, key, val, addedLeaf);
      case INDEX_NODE:
        return assocIndex(root, shift, hash, key, val, addedLeaf);
      case COLLISION_NODE:
        return assocCollision(root, shift, hash, key, val, addedLeaf);
    }
  }
  /**
   * @template T,K,V
   * @type {AssocFunction<ArrayNode<K,V>,K,V>}
   */
  function assocArray(root, shift, hash, key, val, addedLeaf) {
    const idx = mask(hash, shift);
    const node = root.array[idx];
    // if the corresponding index is empty set the index to a newly created node
    if (node === undefined) {
      addedLeaf.val = true;
      return {
        type: ARRAY_NODE,
        size: root.size + 1,
        array: cloneAndSet(root.array, idx, { type: ENTRY, k: key, v: val }),
      };
    }
    if (node.type === ENTRY) {
      // if keys are equal replace the entry
      if (isEqual(key, node.k)) {
        if (val === node.v) {
          return root;
        }
        return {
          type: ARRAY_NODE,
          size: root.size,
          array: cloneAndSet(root.array, idx, {
            type: ENTRY,
            k: key,
            v: val,
          }),
        };
      }
      // otherwise upgrade the entry to a node and insert
      addedLeaf.val = true;
      return {
        type: ARRAY_NODE,
        size: root.size,
        array: cloneAndSet(
          root.array,
          idx,
          createNode(shift + SHIFT, node.k, node.v, hash, key, val)
        ),
      };
    }
    // otherwise call assoc on the child node
    const n = assoc(node, shift + SHIFT, hash, key, val, addedLeaf);
    // if the child node hasn't changed just return the old root
    if (n === node) {
      return root;
    }
    // otherwise set the index to the new node
    return {
      type: ARRAY_NODE,
      size: root.size,
      array: cloneAndSet(root.array, idx, n),
    };
  }
  /**
   * @template T,K,V
   * @type {AssocFunction<IndexNode<K,V>,K,V>}
   */
  function assocIndex(root, shift, hash, key, val, addedLeaf) {
    const bit = bitpos(hash, shift);
    const idx = index$1(root.bitmap, bit);
    // if there is already a item at this hash index..
    if ((root.bitmap & bit) !== 0) {
      // if there is a node at the index (not an entry), call assoc on the child node
      const node = root.array[idx];
      if (node.type !== ENTRY) {
        const n = assoc(node, shift + SHIFT, hash, key, val, addedLeaf);
        if (n === node) {
          return root;
        }
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap,
          array: cloneAndSet(root.array, idx, n),
        };
      }
      // otherwise there is an entry at the index
      // if the keys are equal replace the entry with the updated value
      const nodeKey = node.k;
      if (isEqual(key, nodeKey)) {
        if (val === node.v) {
          return root;
        }
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap,
          array: cloneAndSet(root.array, idx, {
            type: ENTRY,
            k: key,
            v: val,
          }),
        };
      }
      // if the keys are not equal, replace the entry with a new child node
      addedLeaf.val = true;
      return {
        type: INDEX_NODE,
        bitmap: root.bitmap,
        array: cloneAndSet(
          root.array,
          idx,
          createNode(shift + SHIFT, nodeKey, node.v, hash, key, val)
        ),
      };
    } else {
      // else there is currently no item at the hash index
      const n = root.array.length;
      // if the number of nodes is at the maximum, expand this node into an array node
      if (n >= MAX_INDEX_NODE) {
        // create a 32 length array for the new array node (one for each bit in the hash)
        const nodes = new Array(32);
        // create and insert a node for the new entry
        const jdx = mask(hash, shift);
        nodes[jdx] = assocIndex(EMPTY, shift + SHIFT, hash, key, val, addedLeaf);
        let j = 0;
        let bitmap = root.bitmap;
        // place each item in the index node into the correct spot in the array node
        // loop through all 32 bits / array positions
        for (let i = 0; i < 32; i++) {
          if ((bitmap & 1) !== 0) {
            const node = root.array[j++];
            nodes[i] = node;
          }
          // shift the bitmap to process the next bit
          bitmap = bitmap >>> 1;
        }
        return {
          type: ARRAY_NODE,
          size: n + 1,
          array: nodes,
        };
      } else {
        // else there is still space in this index node
        // simply insert a new entry at the hash index
        const newArray = spliceIn(root.array, idx, {
          type: ENTRY,
          k: key,
          v: val,
        });
        addedLeaf.val = true;
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap | bit,
          array: newArray,
        };
      }
    }
  }
  /**
   * @template T,K,V
   * @type {AssocFunction<CollisionNode<K,V>,K,V>}
   */
  function assocCollision(root, shift, hash, key, val, addedLeaf) {
    // if there is a hash collision
    if (hash === root.hash) {
      const idx = collisionIndexOf(root, key);
      // if this key already exists replace the entry with the new value
      if (idx !== -1) {
        const entry = root.array[idx];
        if (entry.v === val) {
          return root;
        }
        return {
          type: COLLISION_NODE,
          hash: hash,
          array: cloneAndSet(root.array, idx, { type: ENTRY, k: key, v: val }),
        };
      }
      // otherwise insert the entry at the end of the array
      const size = root.array.length;
      addedLeaf.val = true;
      return {
        type: COLLISION_NODE,
        hash: hash,
        array: cloneAndSet(root.array, size, { type: ENTRY, k: key, v: val }),
      };
    }
    // if there is no hash collision, upgrade to an index node
    return assoc(
      {
        type: INDEX_NODE,
        bitmap: bitpos(root.hash, shift),
        array: [root],
      },
      shift,
      hash,
      key,
      val,
      addedLeaf
    );
  }
  /**
   * Find the index of a key in the collision node's array
   * @template K,V
   * @param {CollisionNode<K,V>} root
   * @param {K} key
   * @returns {number}
   */
  function collisionIndexOf(root, key) {
    const size = root.array.length;
    for (let i = 0; i < size; i++) {
      if (isEqual(key, root.array[i].k)) {
        return i;
      }
    }
    return -1;
  }
  /**
   * @template T,K,V
   * @callback FindFunction
   * @param {T} root
   * @param {number} shift
   * @param {number} hash
   * @param {K} key
   * @returns {undefined | Entry<K,V>}
   */
  /**
   * Return the found entry or undefined if not present in the root
   * @template K,V
   * @type {FindFunction<Node<K,V>,K,V>}
   */
  function find(root, shift, hash, key) {
    switch (root.type) {
      case ARRAY_NODE:
        return findArray(root, shift, hash, key);
      case INDEX_NODE:
        return findIndex(root, shift, hash, key);
      case COLLISION_NODE:
        return findCollision(root, key);
    }
  }
  /**
   * @template K,V
   * @type {FindFunction<ArrayNode<K,V>,K,V>}
   */
  function findArray(root, shift, hash, key) {
    const idx = mask(hash, shift);
    const node = root.array[idx];
    if (node === undefined) {
      return undefined;
    }
    if (node.type !== ENTRY) {
      return find(node, shift + SHIFT, hash, key);
    }
    if (isEqual(key, node.k)) {
      return node;
    }
    return undefined;
  }
  /**
   * @template K,V
   * @type {FindFunction<IndexNode<K,V>,K,V>}
   */
  function findIndex(root, shift, hash, key) {
    const bit = bitpos(hash, shift);
    if ((root.bitmap & bit) === 0) {
      return undefined;
    }
    const idx = index$1(root.bitmap, bit);
    const node = root.array[idx];
    if (node.type !== ENTRY) {
      return find(node, shift + SHIFT, hash, key);
    }
    if (isEqual(key, node.k)) {
      return node;
    }
    return undefined;
  }
  /**
   * @template K,V
   * @param {CollisionNode<K,V>} root
   * @param {K} key
   * @returns {undefined | Entry<K,V>}
   */
  function findCollision(root, key) {
    const idx = collisionIndexOf(root, key);
    if (idx < 0) {
      return undefined;
    }
    return root.array[idx];
  }
  /**
   * @template T,K,V
   * @callback WithoutFunction
   * @param {T} root
   * @param {number} shift
   * @param {number} hash
   * @param {K} key
   * @returns {undefined | Node<K,V>}
   */
  /**
   * Remove an entry from the root, returning the updated root.
   * Returns undefined if the node should be removed from the parent.
   * @template K,V
   * @type {WithoutFunction<Node<K,V>,K,V>}
   * */
  function without(root, shift, hash, key) {
    switch (root.type) {
      case ARRAY_NODE:
        return withoutArray(root, shift, hash, key);
      case INDEX_NODE:
        return withoutIndex(root, shift, hash, key);
      case COLLISION_NODE:
        return withoutCollision(root, key);
    }
  }
  /**
   * @template K,V
   * @type {WithoutFunction<ArrayNode<K,V>,K,V>}
   */
  function withoutArray(root, shift, hash, key) {
    const idx = mask(hash, shift);
    const node = root.array[idx];
    if (node === undefined) {
      return root; // already empty
    }
    let n = undefined;
    // if node is an entry and the keys are not equal there is nothing to remove
    // if node is not an entry do a recursive call
    if (node.type === ENTRY) {
      if (!isEqual(node.k, key)) {
        return root; // no changes
      }
    } else {
      n = without(node, shift + SHIFT, hash, key);
      if (n === node) {
        return root; // no changes
      }
    }
    // if the recursive call returned undefined the node should be removed
    if (n === undefined) {
      // if the number of child nodes is at the minimum, pack into an index node
      if (root.size <= MIN_ARRAY_NODE) {
        const arr = root.array;
        const out = new Array(root.size - 1);
        let i = 0;
        let j = 0;
        let bitmap = 0;
        while (i < idx) {
          const nv = arr[i];
          if (nv !== undefined) {
            out[j] = nv;
            bitmap |= 1 << i;
            ++j;
          }
          ++i;
        }
        ++i; // skip copying the removed node
        while (i < arr.length) {
          const nv = arr[i];
          if (nv !== undefined) {
            out[j] = nv;
            bitmap |= 1 << i;
            ++j;
          }
          ++i;
        }
        return {
          type: INDEX_NODE,
          bitmap: bitmap,
          array: out,
        };
      }
      return {
        type: ARRAY_NODE,
        size: root.size - 1,
        array: cloneAndSet(root.array, idx, n),
      };
    }
    return {
      type: ARRAY_NODE,
      size: root.size,
      array: cloneAndSet(root.array, idx, n),
    };
  }
  /**
   * @template K,V
   * @type {WithoutFunction<IndexNode<K,V>,K,V>}
   */
  function withoutIndex(root, shift, hash, key) {
    const bit = bitpos(hash, shift);
    if ((root.bitmap & bit) === 0) {
      return root; // already empty
    }
    const idx = index$1(root.bitmap, bit);
    const node = root.array[idx];
    // if the item is not an entry
    if (node.type !== ENTRY) {
      const n = without(node, shift + SHIFT, hash, key);
      if (n === node) {
        return root; // no changes
      }
      // if not undefined, the child node still has items, so update it
      if (n !== undefined) {
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap,
          array: cloneAndSet(root.array, idx, n),
        };
      }
      // otherwise the child node should be removed
      // if it was the only child node, remove this node from the parent
      if (root.bitmap === bit) {
        return undefined;
      }
      // otherwise just remove the child node
      return {
        type: INDEX_NODE,
        bitmap: root.bitmap ^ bit,
        array: spliceOut(root.array, idx),
      };
    }
    // otherwise the item is an entry, remove it if the key matches
    if (isEqual(key, node.k)) {
      if (root.bitmap === bit) {
        return undefined;
      }
      return {
        type: INDEX_NODE,
        bitmap: root.bitmap ^ bit,
        array: spliceOut(root.array, idx),
      };
    }
    return root;
  }
  /**
   * @template K,V
   * @param {CollisionNode<K,V>} root
   * @param {K} key
   * @returns {undefined | Node<K,V>}
   */
  function withoutCollision(root, key) {
    const idx = collisionIndexOf(root, key);
    // if the key not found, no changes
    if (idx < 0) {
      return root;
    }
    // otherwise the entry was found, remove it
    // if it was the only entry in this node, remove the whole node
    if (root.array.length === 1) {
      return undefined;
    }
    // otherwise just remove the entry
    return {
      type: COLLISION_NODE,
      hash: root.hash,
      array: spliceOut(root.array, idx),
    };
  }
  /**
   * @template K,V
   * @param {undefined | Node<K,V>} root
   * @param {(value:V,key:K)=>void} fn
   * @returns {void}
   */
  function forEach(root, fn) {
    if (root === undefined) {
      return;
    }
    const items = root.array;
    const size = items.length;
    for (let i = 0; i < size; i++) {
      const item = items[i];
      if (item === undefined) {
        continue;
      }
      if (item.type === ENTRY) {
        fn(item.v, item.k);
        continue;
      }
      forEach(item, fn);
    }
  }
  /**
   * Extra wrapper to keep track of Dict size and clean up the API
   * @template K,V
   */
  class Dict {
    /**
     * @template V
     * @param {Record<string,V>} o
     * @returns {Dict<string,V>}
     */
    static fromObject(o) {
      const keys = Object.keys(o);
      /** @type Dict<string,V> */
      let m = Dict.new();
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        m = m.set(k, o[k]);
      }
      return m;
    }
    /**
     * @template K,V
     * @param {Map<K,V>} o
     * @returns {Dict<K,V>}
     */
    static fromMap(o) {
      /** @type Dict<K,V> */
      let m = Dict.new();
      o.forEach((v, k) => {
        m = m.set(k, v);
      });
      return m;
    }
    static new() {
      return new Dict(undefined, 0);
    }
    /**
     * @param {undefined | Node<K,V>} root
     * @param {number} size
     */
    constructor(root, size) {
      this.root = root;
      this.size = size;
    }
    /**
     * @template NotFound
     * @param {K} key
     * @param {NotFound} notFound
     * @returns {NotFound | V}
     */
    get(key, notFound) {
      if (this.root === undefined) {
        return notFound;
      }
      const found = find(this.root, 0, getHash(key), key);
      if (found === undefined) {
        return notFound;
      }
      return found.v;
    }
    /**
     * @param {K} key
     * @param {V} val
     * @returns {Dict<K,V>}
     */
    set(key, val) {
      const addedLeaf = { val: false };
      const root = this.root === undefined ? EMPTY : this.root;
      const newRoot = assoc(root, 0, getHash(key), key, val, addedLeaf);
      if (newRoot === this.root) {
        return this;
      }
      return new Dict(newRoot, addedLeaf.val ? this.size + 1 : this.size);
    }
    /**
     * @param {K} key
     * @returns {Dict<K,V>}
     */
    delete(key) {
      if (this.root === undefined) {
        return this;
      }
      const newRoot = without(this.root, 0, getHash(key), key);
      if (newRoot === this.root) {
        return this;
      }
      if (newRoot === undefined) {
        return Dict.new();
      }
      return new Dict(newRoot, this.size - 1);
    }
    /**
     * @param {K} key
     * @returns {boolean}
     */
    has(key) {
      if (this.root === undefined) {
        return false;
      }
      return find(this.root, 0, getHash(key), key) !== undefined;
    }
    /**
     * @returns {[K,V][]}
     */
    entries() {
      if (this.root === undefined) {
        return [];
      }
      /** @type [K,V][] */
      const result = [];
      this.forEach((v, k) => result.push([k, v]));
      return result;
    }
    /**
     *
     * @param {(val:V,key:K)=>void} fn
     */
    forEach(fn) {
      forEach(this.root, fn);
    }
    hashCode() {
      let h = 0;
      this.forEach((v, k) => {
        h = (h + hashMerge(getHash(v), getHash(k))) | 0;
      });
      return h;
    }
    /**
     * @param {unknown} o
     * @returns {boolean}
     */
    equals(o) {
      if (!(o instanceof Dict) || this.size !== o.size) {
        return false;
      }
      let equal = true;
      this.forEach((v, k) => {
        equal = equal && isEqual(o.get(k, !v), v);
      });
      return equal;
    }
  }

  const Nil = undefined;
  const NOT_FOUND = {};

  function identity$1(x) {
    return x;
  }

  function to_string(term) {
    return term.toString();
  }

  function concat$1(xs) {
    let result = "";
    for (const x of xs) {
      result = result + x;
    }
    return result;
  }

  function print_debug(string) {
    if (typeof process === "object" && process.stderr?.write) {
      process.stderr.write(string + "\n"); // If we're in Node.js, use `stderr`
    } else if (typeof Deno === "object") {
      Deno.stderr.writeSync(new TextEncoder().encode(string + "\n")); // If we're in Deno, use `stderr`
    } else {
      console.log(string); // Otherwise, use `console.log` (so that it doesn't look like an error)
    }
  }

  function new_map() {
    return Dict.new();
  }

  function map_to_list(map) {
    return List.fromArray(map.entries());
  }

  function map_get(map, key) {
    const value = map.get(key, NOT_FOUND);
    if (value === NOT_FOUND) {
      return new Error(Nil);
    }
    return new Ok(value);
  }

  function map_insert(key, value, map) {
    return map.set(key, value);
  }

  function classify_dynamic(data) {
    if (typeof data === "string") {
      return "String";
    } else if (data instanceof Result) {
      return "Result";
    } else if (data instanceof List) {
      return "List";
    } else if (data instanceof BitArray) {
      return "BitArray";
    } else if (data instanceof Dict) {
      return "Map";
    } else if (Number.isInteger(data)) {
      return "Int";
    } else if (Array.isArray(data)) {
      return `Tuple of ${data.length} elements`;
    } else if (typeof data === "number") {
      return "Float";
    } else if (data === null) {
      return "Null";
    } else if (data === undefined) {
      return "Nil";
    } else {
      const type = typeof data;
      return type.charAt(0).toUpperCase() + type.slice(1);
    }
  }

  function decoder_error(expected, got) {
    return decoder_error_no_classify(expected, classify_dynamic(got));
  }

  function decoder_error_no_classify(expected, got) {
    return new Error(
      List.fromArray([new DecodeError(expected, got, List.fromArray([]))])
    );
  }

  function decode_string(data) {
    return typeof data === "string"
      ? new Ok(data)
      : decoder_error("String", data);
  }

  function decode_int(data) {
    return Number.isInteger(data) ? new Ok(data) : decoder_error("Int", data);
  }

  function decode_bool(data) {
    return typeof data === "boolean" ? new Ok(data) : decoder_error("Bool", data);
  }

  function decode_tuple2(data) {
    return decode_tupleN(data, 2);
  }

  function decode_tuple3(data) {
    return decode_tupleN(data, 3);
  }

  function decode_tupleN(data, n) {
    if (Array.isArray(data) && data.length == n) {
      return new Ok(data);
    }

    const list = decode_exact_length_list(data, n);
    if (list) return new Ok(list);

    return decoder_error(`Tuple of ${n} elements`, data);
  }

  function decode_exact_length_list(data, n) {
    if (!(data instanceof List)) return;

    const elements = [];
    let current = data;

    for (let i = 0; i < n; i++) {
      if (!(current instanceof NonEmpty)) break;
      elements.push(current.head);
      current = current.tail;
    }

    if (elements.length === n && !(current instanceof NonEmpty)) return elements;
  }

  function decode_list(data) {
    if (Array.isArray(data)) {
      return new Ok(List.fromArray(data));
    }
    return data instanceof List ? new Ok(data) : decoder_error("List", data);
  }

  function decode_field(value, name) {
    const not_a_map_error = () => decoder_error("Map", value);

    if (
      value instanceof Dict ||
      value instanceof WeakMap ||
      value instanceof Map
    ) {
      const entry = map_get(value, name);
      return new Ok(entry.isOk() ? new Some(entry[0]) : new None());
    } else if (Object.getPrototypeOf(value) == Object.prototype) {
      return try_get_field(value, name, () => new Ok(new None()));
    } else {
      return try_get_field(value, name, not_a_map_error);
    }
  }

  function try_get_field(value, field, or_else) {
    try {
      return field in value ? new Ok(new Some(value[field])) : or_else();
    } catch {
      return or_else();
    }
  }

  function inspect$1(v) {
    const t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$1).join(", ")})`;
    if (v instanceof List) return inspectList(v);
    if (v instanceof UtfCodepoint) return inspectUtfCodepoint(v);
    if (v instanceof BitArray) return inspectBitArray(v);
    if (v instanceof CustomType) return inspectCustomType(v);
    if (v instanceof Dict) return inspectDict(v);
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$1).join(", ")}))`;
    if (v instanceof RegExp) return `//js(${v})`;
    if (v instanceof Date) return `//js(Date("${v.toISOString()}"))`;
    if (v instanceof Function) {
      const args = [];
      for (const i of Array(v.length).keys())
        args.push(String.fromCharCode(i + 97));
      return `//fn(${args.join(", ")}) { ... }`;
    }
    return inspectObject(v);
  }

  function inspectDict(map) {
    let body = "dict.from_list([";
    let first = true;
    map.forEach((value, key) => {
      if (!first) body = body + ", ";
      body = body + "#(" + inspect$1(key) + ", " + inspect$1(value) + ")";
      first = false;
    });
    return body + "])";
  }

  function inspectObject(v) {
    const name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    const props = [];
    for (const k of Object.keys(v)) {
      props.push(`${inspect$1(k)}: ${inspect$1(v[k])}`);
    }
    const body = props.length ? " " + props.join(", ") + " " : "";
    const head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function inspectCustomType(record) {
    const props = Object.keys(record)
      .map((label) => {
        const value = inspect$1(record[label]);
        return isNaN(parseInt(label)) ? `${label}: ${value}` : value;
      })
      .join(", ");
    return props
      ? `${record.constructor.name}(${props})`
      : record.constructor.name;
  }

  function inspectList(list) {
    return `[${list.toArray().map(inspect$1).join(", ")}]`;
  }

  function inspectBitArray(bits) {
    return `<<${Array.from(bits.buffer).join(", ")}>>`;
  }

  function inspectUtfCodepoint(codepoint) {
    return `//utfcodepoint(${String.fromCodePoint(codepoint.value)})`;
  }

  function to_list(dict) {
    return map_to_list(dict);
  }

  function new$() {
    return new_map();
  }

  function get(from, get) {
    return map_get(from, get);
  }

  function insert(dict, key, value) {
    return map_insert(key, value, dict);
  }

  function update(dict, key, fun) {
    let _pipe = dict;
    let _pipe$1 = get(_pipe, key);
    let _pipe$2 = from_result(_pipe$1);
    let _pipe$3 = fun(_pipe$2);
    return ((_capture) => { return insert(dict, key, _capture); })(_pipe$3);
  }

  function concat(strings) {
    let _pipe = strings;
    let _pipe$1 = from_strings(_pipe);
    return to_string$1(_pipe$1);
  }

  function inspect(term) {
    let _pipe = inspect$1(term);
    return to_string$1(_pipe);
  }

  function object$1(entries) {
    return Object.fromEntries(entries);
  }

  function identity(x) {
    return x;
  }

  function array$1(list) {
    return list.toArray();
  }

  function string$1(input) {
    return identity(input);
  }

  function bool$1(input) {
    return identity(input);
  }

  function int$1(input) {
    return identity(input);
  }

  function object(entries) {
    return object$1(entries);
  }

  function preprocessed_array(from) {
    return array$1(from);
  }

  function array(entries, inner_type) {
    let _pipe = entries;
    let _pipe$1 = map$1(_pipe, inner_type);
    return preprocessed_array(_pipe$1);
  }

  function postMessage(worker, message) {
    worker.postMessage(message);
  }

  function onMessage(worker, callback) {
    worker.addEventListener("message", function (message) {
      callback(message.data);
    });
  }

  class B extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class I extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class S extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class L extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class DB extends CustomType {
    constructor(triples, entity_index, attribute_index, value_index) {
      super();
      this.triples = triples;
      this.entity_index = entity_index;
      this.attribute_index = attribute_index;
      this.value_index = value_index;
    }
  }

  function push(current, t) {
    if (current instanceof None) {
      return toList([t]);
    } else if (current instanceof Some) {
      let ts = current[0];
      return append(ts, toList([t]));
    } else {
      throw makeError(
        "case_no_match",
        "magpie/store/in_memory",
        25,
        "push",
        "No case clause matched",
        { values: [current] }
      )
    }
  }

  function index(triples, by) {
    return fold(
      triples,
      new$(),
      (acc, t) => {
        return update(
          acc,
          by(t),
          (_capture) => { return push(_capture, t); },
        );
      },
    );
  }

  function create_db(triples) {
    return new DB(
      triples,
      index(triples, (t) => { return t[0]; }),
      index(triples, (t) => { return t[1]; }),
      index(triples, (t) => { return t[2]; }),
    );
  }

  function value$1() {
    return (x) => {
      return any(
        toList([
          decode1(
            (var0) => { return new B(var0); },
            field("b", bool$2),
          ),
          decode1(
            (var0) => { return new I(var0); },
            field("i", int$2),
          ),
          decode1(
            (var0) => { return new S(var0); },
            field("s", string$2),
          ),
          decode1(
            (var0) => { return new L(var0); },
            field("l", list$1(value$1())),
          ),
        ]),
      )(x);
    };
  }

  function decoder$1() {
    return list$1(tuple3$1(int$2, string$2, value$1()));
  }

  function data(){
    return [[100,"person/name",{"s":"James Cameron"}],[100,"person/born",{"s":"1954-08-16T00:00:00Z"}],[101,"person/name",{"s":"Arnold Schwarzenegger"}],[101,"person/born",{"s":"1947-07-30T00:00:00Z"}],[102,"person/name",{"s":"Linda Hamilton"}],[102,"person/born",{"s":"1956-09-26T00:00:00Z"}],[103,"person/name",{"s":"Michael Biehn"}],[103,"person/born",{"s":"1956-07-31T00:00:00Z"}],[104,"person/name",{"s":"Ted Kotcheff"}],[104,"person/born",{"s":"1931-04-07T00:00:00Z"}],[105,"person/name",{"s":"Sylvester Stallone"}],[105,"person/born",{"s":"1946-07-06T00:00:00Z"}],[106,"person/name",{"s":"Richard Crenna"}],[106,"person/born",{"s":"1926-11-30T00:00:00Z"}],[106,"person/death",{"s":"2003-01-17T00:00:00Z"}],[107,"person/name",{"s":"Brian Dennehy"}],[107,"person/born",{"s":"1938-07-09T00:00:00Z"}],[108,"person/name",{"s":"John McTiernan"}],[108,"person/born",{"s":"1951-01-08T00:00:00Z"}],[109,"person/name",{"s":"Elpidia Carrillo"}],[109,"person/born",{"s":"1961-08-16T00:00:00Z"}],[110,"person/name",{"s":"Carl Weathers"}],[110,"person/born",{"s":"1948-01-14T00:00:00Z"}],[111,"person/name",{"s":"Richard Donner"}],[111,"person/born",{"s":"1930-04-24T00:00:00Z"}],[112,"person/name",{"s":"Mel Gibson"}],[112,"person/born",{"s":"1956-01-03T00:00:00Z"}],[113,"person/name",{"s":"Danny Glover"}],[113,"person/born",{"s":"1946-07-22T00:00:00Z"}],[114,"person/name",{"s":"Gary Busey"}],[114,"person/born",{"s":"1944-07-29T00:00:00Z"}],[115,"person/name",{"s":"Paul Verhoeven"}],[115,"person/born",{"s":"1938-07-18T00:00:00Z"}],[116,"person/name",{"s":"Peter Weller"}],[116,"person/born",{"s":"1947-06-24T00:00:00Z"}],[117,"person/name",{"s":"Nancy Allen"}],[117,"person/born",{"s":"1950-06-24T00:00:00Z"}],[118,"person/name",{"s":"Ronny Cox"}],[118,"person/born",{"s":"1938-07-23T00:00:00Z"}],[119,"person/name",{"s":"Mark L. Lester"}],[119,"person/born",{"s":"1946-11-26T00:00:00Z"}],[120,"person/name",{"s":"Rae Dawn Chong"}],[120,"person/born",{"s":"1961-02-28T00:00:00Z"}],[121,"person/name",{"s":"Alyssa Milano"}],[121,"person/born",{"s":"1972-12-19T00:00:00Z"}],[122,"person/name",{"s":"Bruce Willis"}],[122,"person/born",{"s":"1955-03-19T00:00:00Z"}],[123,"person/name",{"s":"Alan Rickman"}],[123,"person/born",{"s":"1946-02-21T00:00:00Z"}],[124,"person/name",{"s":"Alexander Godunov"}],[124,"person/born",{"s":"1949-11-28T00:00:00Z"}],[124,"person/death",{"s":"1995-05-18T00:00:00Z"}],[125,"person/name",{"s":"Robert Patrick"}],[125,"person/born",{"s":"1958-11-05T00:00:00Z"}],[126,"person/name",{"s":"Edward Furlong"}],[126,"person/born",{"s":"1977-08-02T00:00:00Z"}],[127,"person/name",{"s":"Jonathan Mostow"}],[127,"person/born",{"s":"1961-11-28T00:00:00Z"}],[128,"person/name",{"s":"Nick Stahl"}],[128,"person/born",{"s":"1979-12-05T00:00:00Z"}],[129,"person/name",{"s":"Claire Danes"}],[129,"person/born",{"s":"1979-04-12T00:00:00Z"}],[130,"person/name",{"s":"George P. Cosmatos"}],[130,"person/born",{"s":"1941-01-04T00:00:00Z"}],[130,"person/death",{"s":"2005-04-19T00:00:00Z"}],[131,"person/name",{"s":"Charles Napier"}],[131,"person/born",{"s":"1936-04-12T00:00:00Z"}],[131,"person/death",{"s":"2011-10-05T00:00:00Z"}],[132,"person/name",{"s":"Peter MacDonald"}],[133,"person/name",{"s":"Marc de Jonge"}],[133,"person/born",{"s":"1949-02-16T00:00:00Z"}],[133,"person/death",{"s":"1996-06-06T00:00:00Z"}],[134,"person/name",{"s":"Stephen Hopkins"}],[135,"person/name",{"s":"Ruben Blades"}],[135,"person/born",{"s":"1948-07-16T00:00:00Z"}],[136,"person/name",{"s":"Joe Pesci"}],[136,"person/born",{"s":"1943-02-09T00:00:00Z"}],[137,"person/name",{"s":"Ridley Scott"}],[137,"person/born",{"s":"1937-11-30T00:00:00Z"}],[138,"person/name",{"s":"Tom Skerritt"}],[138,"person/born",{"s":"1933-08-25T00:00:00Z"}],[139,"person/name",{"s":"Sigourney Weaver"}],[139,"person/born",{"s":"1949-10-08T00:00:00Z"}],[140,"person/name",{"s":"Veronica Cartwright"}],[140,"person/born",{"s":"1949-04-20T00:00:00Z"}],[141,"person/name",{"s":"Carrie Henn"}],[142,"person/name",{"s":"George Miller"}],[142,"person/born",{"s":"1945-03-03T00:00:00Z"}],[143,"person/name",{"s":"Steve Bisley"}],[143,"person/born",{"s":"1951-12-26T00:00:00Z"}],[144,"person/name",{"s":"Joanne Samuel"}],[145,"person/name",{"s":"Michael Preston"}],[145,"person/born",{"s":"1938-05-14T00:00:00Z"}],[146,"person/name",{"s":"Bruce Spence"}],[146,"person/born",{"s":"1945-09-17T00:00:00Z"}],[147,"person/name",{"s":"George Ogilvie"}],[147,"person/born",{"s":"1931-03-05T00:00:00Z"}],[148,"person/name",{"s":"Tina Turner"}],[148,"person/born",{"s":"1939-11-26T00:00:00Z"}],[149,"person/name",{"s":"Sophie Marceau"}],[149,"person/born",{"s":"1966-11-17T00:00:00Z"}],[200,"movie/title",{"s":"The Terminator"}],[200,"movie/year",{"i":1984}],[200,"movie/director",{"i":100}],[200,"movie/cast",{"i":101}],[200,"movie/cast",{"i":102}],[200,"movie/cast",{"i":103}],[200,"movie/sequel",{"i":207}],[201,"movie/title",{"s":"First Blood"}],[201,"movie/year",{"i":1982}],[201,"movie/director",{"i":104}],[201,"movie/cast",{"i":105}],[201,"movie/cast",{"i":106}],[201,"movie/cast",{"i":107}],[201,"movie/sequel",{"i":209}],[202,"movie/title",{"s":"Predator"}],[202,"movie/year",{"i":1987}],[202,"movie/director",{"i":108}],[202,"movie/cast",{"i":101}],[202,"movie/cast",{"i":109}],[202,"movie/cast",{"i":110}],[202,"movie/sequel",{"i":211}],[203,"movie/title",{"s":"Lethal Weapon"}],[203,"movie/year",{"i":1987}],[203,"movie/director",{"i":111}],[203,"movie/cast",{"i":112}],[203,"movie/cast",{"i":113}],[203,"movie/cast",{"i":114}],[203,"movie/sequel",{"i":212}],[204,"movie/title",{"s":"RoboCop"}],[204,"movie/year",{"i":1987}],[204,"movie/director",{"i":115}],[204,"movie/cast",{"i":116}],[204,"movie/cast",{"i":117}],[204,"movie/cast",{"i":118}],[205,"movie/title",{"s":"Commando"}],[205,"movie/year",{"i":1985}],[205,"movie/director",{"i":119}],[205,"movie/cast",{"i":101}],[205,"movie/cast",{"i":120}],[205,"movie/cast",{"i":121}],[205,"trivia",{"s":"In 1986, a sequel was written with an eye to having\n  John McTiernan direct. Schwarzenegger wasn't interested in reprising\n  the role. The script was then reworked with a new central character,\n  eventually played by Bruce Willis, and became Die Hard"}],[206,"movie/title",{"s":"Die Hard"}],[206,"movie/year",{"i":1988}],[206,"movie/director",{"i":108}],[206,"movie/cast",{"i":122}],[206,"movie/cast",{"i":123}],[206,"movie/cast",{"i":124}],[207,"movie/title",{"s":"Terminator 2: Judgment Day"}],[207,"movie/year",{"i":1991}],[207,"movie/director",{"i":100}],[207,"movie/cast",{"i":101}],[207,"movie/cast",{"i":102}],[207,"movie/cast",{"i":125}],[207,"movie/cast",{"i":126}],[207,"movie/sequel",{"i":208}],[208,"movie/title",{"s":"Terminator 3: Rise of the Machines"}],[208,"movie/year",{"i":2003}],[208,"movie/director",{"i":127}],[208,"movie/cast",{"i":101}],[208,"movie/cast",{"i":128}],[208,"movie/cast",{"i":129}],[209,"movie/title",{"s":"Rambo: First Blood Part II"}],[209,"movie/year",{"i":1985}],[209,"movie/director",{"i":130}],[209,"movie/cast",{"i":105}],[209,"movie/cast",{"i":106}],[209,"movie/cast",{"i":131}],[209,"movie/sequel",{"i":210}],[210,"movie/title",{"s":"Rambo III"}],[210,"movie/year",{"i":1988}],[210,"movie/director",{"i":132}],[210,"movie/cast",{"i":105}],[210,"movie/cast",{"i":106}],[210,"movie/cast",{"i":133}],[211,"movie/title",{"s":"Predator 2"}],[211,"movie/year",{"i":1990}],[211,"movie/director",{"i":134}],[211,"movie/cast",{"i":113}],[211,"movie/cast",{"i":114}],[211,"movie/cast",{"i":135}],[212,"movie/title",{"s":"Lethal Weapon 2"}],[212,"movie/year",{"i":1989}],[212,"movie/director",{"i":111}],[212,"movie/cast",{"i":112}],[212,"movie/cast",{"i":113}],[212,"movie/cast",{"i":136}],[212,"movie/sequel",{"i":213}],[213,"movie/title",{"s":"Lethal Weapon 3"}],[213,"movie/year",{"i":1992}],[213,"movie/director",{"i":111}],[213,"movie/cast",{"i":112}],[213,"movie/cast",{"i":113}],[213,"movie/cast",{"i":136}],[214,"movie/title",{"s":"Alien"}],[214,"movie/year",{"i":1979}],[214,"movie/director",{"i":137}],[214,"movie/cast",{"i":138}],[214,"movie/cast",{"i":139}],[214,"movie/cast",{"i":140}],[214,"movie/sequel",{"i":215}],[215,"movie/title",{"s":"Aliens"}],[215,"movie/year",{"i":1986}],[215,"movie/director",{"i":100}],[215,"movie/cast",{"i":139}],[215,"movie/cast",{"i":141}],[215,"movie/cast",{"i":103}],[216,"movie/title",{"s":"Mad Max"}],[216,"movie/year",{"i":1979}],[216,"movie/director",{"i":142}],[216,"movie/cast",{"i":112}],[216,"movie/cast",{"i":143}],[216,"movie/cast",{"i":144}],[216,"movie/sequel",{"i":217}],[217,"movie/title",{"s":"Mad Max 2"}],[217,"movie/year",{"i":1981}],[217,"movie/director",{"i":142}],[217,"movie/cast",{"i":112}],[217,"movie/cast",{"i":145}],[217,"movie/cast",{"i":146}],[217,"movie/sequel",{"i":218}],[218,"movie/title",{"s":"Mad Max Beyond Thunderdome"}],[218,"movie/year",{"i":1985}],[218,"movie/director",{"s":"user"}],[218,"movie/director",{"i":147}],[218,"movie/cast",{"i":112}],[218,"movie/cast",{"i":148}],[219,"movie/title",{"s":"Braveheart"}],[219,"movie/year",{"i":1995}],[219,"movie/director",{"i":112}],[219,"movie/cast",{"i":112}],[219,"movie/cast",{"i":149}]]
  }

  function triples() {
    let $ = decoder$1()(data());
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "magpie/browser/loader",
        9,
        "triples",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let triples$1 = $[0];
    return triples$1;
  }

  function db() {
    return create_db(triples());
  }

  function curry2(fun) {
    return (a) => { return (b) => { return fun(a, b); }; };
  }

  function curry3(fun) {
    return (a) => { return (b) => { return (c) => { return fun(a, b, c); }; }; };
  }

  function curry4(fun) {
    return (a) => {
      return (b) => {
        return (c) => { return (d) => { return fun(a, b, c, d); }; };
      };
    };
  }

  class Codec extends CustomType {
    constructor(encode, decode) {
      super();
      this.encode = encode;
      this.decode = decode;
    }
  }

  class Builder extends CustomType {
    constructor(match, decoder) {
      super();
      this.match = match;
      this.decoder = decoder;
    }
  }

  function from(encode, decode) {
    return new Codec(encode, decode);
  }

  function container(codec, encode, decode) {
    return new Codec(encode(codec.encode), decode(codec.decode));
  }

  function int() {
    return new Codec(int$1, int$2);
  }

  function string() {
    return new Codec(string$1, string$2);
  }

  function list(codec) {
    return container(
      codec,
      (inner) => { return (_capture) => { return array(_capture, inner); }; },
      list$1,
    );
  }

  function custom1(match) {
    return new Builder(curry2(match), new$());
  }

  function custom2(match) {
    return new Builder(curry3(match), new$());
  }

  function custom3(match) {
    return new Builder(curry4(match), new$());
  }

  function variant(builder, tag, matcher, decoder) {
    let encode = (vals) => {
      let fields = index_map(
        vals,
        (i, json) => { return [to_string$2(i), json]; },
      );
      let tag$1 = ["$", string$1(tag)];
      return object(toList([tag$1], fields));
    };
    return new Builder(
      builder.match(matcher(encode)),
      insert(builder.decoder, tag, decoder),
    );
  }

  function construct(builder) {
    return new Codec(
      builder.match,
      (dyn) => {
        let _pipe = dyn;
        let _pipe$1 = field("$", string$2)(_pipe);
        return then$(
          _pipe$1,
          (tag) => {
            let $ = get(builder.decoder, tag);
            if ($.isOk()) {
              let decoder$1 = $[0];
              return decoder$1(dyn);
            } else if (!$.isOk()) {
              return new Error(toList([]));
            } else {
              throw makeError(
                "case_no_match",
                "gleam_community/codec",
                235,
                "",
                "No case clause matched",
                { values: [$] }
              )
            }
          },
        );
      },
    );
  }

  function encoder(codec) {
    return codec.encode;
  }

  function decoder(codec) {
    return codec.decode;
  }

  function encode_json(value, codec) {
    return codec.encode(value);
  }

  function variant1(builder, tag, value, codec) {
    return variant(
      builder,
      tag,
      (f) => { return (a) => { return f(toList([encode_json(a, codec)])); }; },
      (dyn) => {
        let _pipe = dyn;
        let _pipe$1 = field("0", codec.decode)(_pipe);
        return map(_pipe$1, value);
      },
    );
  }

  function variant2(builder, tag, value, codec_a, codec_b) {
    return variant(
      builder,
      tag,
      (f) => {
        return (a, b) => {
          return f(toList([encode_json(a, codec_a), encode_json(b, codec_b)]));
        };
      },
      decode2(
        value,
        field("0", codec_a.decode),
        field("1", codec_b.decode),
      ),
    );
  }

  function debug(term) {
    let _pipe = term;
    let _pipe$1 = inspect(_pipe);
    print_debug(_pipe$1);
    return term;
  }

  class Variable extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Constant extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function match_part(loop$match, loop$part, loop$context) {
    while (true) {
      let match = loop$match;
      let part = loop$part;
      let context = loop$context;
      if (match instanceof Constant) {
        let value = match[0];
        let $ = isEqual(value, part);
        if ($) {
          return new Ok(context);
        } else if (!$) {
          return new Error(undefined);
        } else {
          throw makeError(
            "case_no_match",
            "magpie/query",
            40,
            "match_part",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else if (match instanceof Variable) {
        let var$ = match[0];
        let $ = get(context, var$);
        if ($.isOk()) {
          let constant = $[0];
          loop$match = new Constant(constant);
          loop$part = part;
          loop$context = context;
        } else if (!$.isOk() && !$[0]) {
          return new Ok(insert(context, var$, part));
        } else {
          throw makeError(
            "case_no_match",
            "magpie/query",
            45,
            "match_part",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "magpie/query",
          38,
          "match_part",
          "No case clause matched",
          { values: [match] }
        )
      }
    }
  }

  function match_pattern(pattern, triple, context) {
    return then$(
      match_part(pattern[0], new I(triple[0]), context),
      (context) => {
        return then$(
          match_part(pattern[1], new S(triple[1]), context),
          (context) => {
            return then$(
              match_part(pattern[2], triple[2], context),
              (context) => { return new Ok(context); },
            );
          },
        );
      },
    );
  }

  function relevant_triples(db, pattern) {
    let _pipe = (() => {
      if (pattern[0] instanceof Constant && pattern[0][0] instanceof I) {
        let id = pattern[0][0][0];
        return get(db.entity_index, id);
      } else if (pattern[1] instanceof Constant && pattern[1][0] instanceof S) {
        let attr = pattern[1][0][0];
        return get(db.attribute_index, attr);
      } else if (pattern[2] instanceof Constant) {
        let value = pattern[2][0];
        return get(db.value_index, value);
      } else {
        return new Error(undefined);
      }
    })();
    return unwrap(_pipe, db.triples);
  }

  function single(pattern, db, context) {
    let _pipe = relevant_triples(db, pattern);
    return filter_map(
      _pipe,
      (_capture) => { return match_pattern(pattern, _capture, context); },
    );
  }

  function where(patterns, db) {
    return fold(
      patterns,
      toList([new$()]),
      (contexts, pattern) => {
        let _pipe = map$1(
          contexts,
          (_capture) => { return single(pattern, db, _capture); },
        );
        return flatten(_pipe);
      },
    );
  }

  function actualize(context, find) {
    return map$1(
      find,
      (f) => {
        let $ = get(context, f);
        if ($.isOk()) {
          let r = $[0];
          return r;
        } else if (!$.isOk() && !$[0]) {
          debug(
            concat(
              toList(["actualize failed due to invalid find key: ", f]),
            ),
          );
          return (() => {
            throw makeError(
              "todo",
              "magpie/query",
              89,
              "",
              "panic expression evaluated",
              {}
            )
          })()("fail");
        } else {
          throw makeError(
            "case_no_match",
            "magpie/query",
            83,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      },
    );
  }

  function run$1(find, patterns, db) {
    let _pipe = where(patterns, db);
    return map$1(_pipe, (_capture) => { return actualize(_capture, find); });
  }

  class Query extends CustomType {
    constructor(find, patterns) {
      super();
      this.find = find;
      this.patterns = patterns;
    }
  }

  class DBView extends CustomType {
    constructor(triple_count, attribute_suggestions) {
      super();
      this.triple_count = triple_count;
      this.attribute_suggestions = attribute_suggestions;
    }
  }

  function tuple3(a, b, c) {
    return from(
      (t) => {
        let v1 = t[0];
        let v2 = t[1];
        let v3 = t[2];
        return array(
          toList([
            encoder(a)(v1),
            encoder(b)(v2),
            encoder(c)(v3),
          ]),
          (x) => { return x; },
        );
      },
      tuple3$1(decoder(a), decoder(b), decoder(c)),
    );
  }

  function tuple2(a, b) {
    return from(
      (t) => {
        let v1 = t[0];
        let v2 = t[1];
        return array(
          toList([encoder(a)(v1), encoder(b)(v2)]),
          (x) => { return x; },
        );
      },
      tuple2$1(decoder(a), decoder(b)),
    );
  }

  function bool() {
    return from(bool$1, bool$2);
  }

  function value() {
    let _pipe = custom3(
      (b, i, s, value) => {
        if (value instanceof B) {
          let value$1 = value[0];
          return b(value$1);
        } else if (value instanceof I) {
          let value$1 = value[0];
          return i(value$1);
        } else if (value instanceof S) {
          let value$1 = value[0];
          return s(value$1);
        } else {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/serialize",
              48,
              "",
              "panic expression evaluated",
              {}
            )
          })()("no lists in dataset and no custom4 in codec");
        }
      },
    );
    let _pipe$1 = variant1(
      _pipe,
      "B",
      (var0) => { return new B(var0); },
      bool(),
    );
    let _pipe$2 = variant1(
      _pipe$1,
      "I",
      (var0) => { return new I(var0); },
      int(),
    );
    let _pipe$3 = variant1(
      _pipe$2,
      "S",
      (var0) => { return new S(var0); },
      string(),
    );
    return construct(_pipe$3);
  }

  function relations() {
    return list(list(value()));
  }

  function db_view() {
    let _pipe = custom1(
      (q, value) => {
        if (!(value instanceof DBView)) {
          throw makeError(
            "assignment_no_match",
            "magpie/browser/serialize",
            92,
            "",
            "Assignment pattern did not match",
            { value: value }
          )
        }
        let triple_count = value.triple_count;
        let attribute_suggestions = value.attribute_suggestions;
        return q(triple_count, attribute_suggestions);
      },
    );
    let _pipe$1 = variant2(
      _pipe,
      "",
      (var0, var1) => { return new DBView(var0, var1); },
      int(),
      list(tuple2(string(), int())),
    );
    return construct(_pipe$1);
  }

  function query() {
    let _pipe = custom1(
      (q, value) => {
        if (!(value instanceof Query)) {
          throw makeError(
            "assignment_no_match",
            "magpie/browser/serialize",
            71,
            "",
            "Assignment pattern did not match",
            { value: value }
          )
        }
        let f = value.find;
        let p = value.patterns;
        return q(f, p);
      },
    );
    let _pipe$1 = variant2(
      _pipe,
      "",
      (var0, var1) => { return new Query(var0, var1); },
      list(string()),
      list(pattern()),
    );
    return construct(_pipe$1);
  }

  function pattern() {
    return tuple3(match(), match(), match());
  }

  function match() {
    let _pipe = custom2(
      (variable, constant, value) => {
        if (value instanceof Variable) {
          let var$ = value[0];
          return variable(var$);
        } else if (value instanceof Constant) {
          let value$1 = value[0];
          return constant(value$1);
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/serialize",
            59,
            "",
            "No case clause matched",
            { values: [value] }
          )
        }
      },
    );
    let _pipe$1 = variant1(
      _pipe,
      "V",
      (var0) => { return new Variable(var0); },
      string(),
    );
    let _pipe$2 = variant1(
      _pipe$1,
      "C",
      (var0) => { return new Constant(var0); },
      value(),
    );
    return construct(_pipe$2);
  }

  function run(self) {
    let db$1 = db();
    let attribute_suggestions = (() => {
      let _pipe = to_list(db$1.attribute_index);
      return map$1(
        _pipe,
        (pair) => {
          let key = pair[0];
          let triples = pair[1];
          return [key, length(triples)];
        },
      );
    })();
    postMessage(
      self,
      db_view().encode(
        new DBView(length(db$1.triples), attribute_suggestions),
      ),
    );
    return onMessage(
      self,
      (data) => {
        let data$1 = from$1(data);
        let $ = query().decode(data$1);
        if ($.isOk() && $[0] instanceof Query) {
          let from = $[0].find;
          let patterns = $[0].patterns;
          let result = run$1(from, patterns, db$1);
          return postMessage(self, relations().encode(result));
        } else if (!$.isOk()) {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/worker",
              41,
              "",
              "panic expression evaluated",
              {}
            )
          })()("couldn't decode");
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/worker",
            36,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      },
    );
  }

  run(self);

})();
