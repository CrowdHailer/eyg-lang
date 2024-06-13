(function () {
  'use strict';

  let CustomType$5 = class CustomType {
    inspect() {
      let field = (label) => {
        let value = inspect$6(this[label]);
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
  };

  let List$3 = class List {
    static fromArray(array, tail) {
      let t = tail || new Empty$5();
      return array.reduceRight((xs, x) => new NonEmpty$3(x, xs), t);
    }

    static isList(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "EmptyList" || variant === "NonEmptyList";
    }

    [Symbol.iterator]() {
      return new ListIterator$3(this);
    }

    inspect() {
      return `[${this.toArray().map(inspect$6).join(", ")}]`;
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
  };

  function toList$2(elements, tail) {
    return List$3.fromArray(elements, tail);
  }

  let ListIterator$3 = class ListIterator {
    #current;

    constructor(current) {
      this.#current = current;
    }

    next() {
      if (this.#current.isEmpty()) {
        return { done: true };
      } else {
        let { head, tail } = this.#current;
        this.#current = tail;
        return { value: head, done: false };
      }
    }
  };

  let Empty$5 = class Empty extends List$3 {
    get __gleam_prelude_variant__() {
      return "EmptyList";
    }

    isEmpty() {
      return true;
    }
  };

  let NonEmpty$3 = class NonEmpty extends List$3 {
    constructor(head, tail) {
      super();
      this.head = head;
      this.tail = tail;
    }

    get __gleam_prelude_variant__() {
      return "NonEmptyList";
    }

    isEmpty() {
      return false;
    }
  };

  let BitString$1 = class BitString {
    static isBitString(data) {
      return data?.__gleam_prelude_variant__ === "BitString";
    }

    constructor(buffer) {
      this.buffer = buffer;
    }

    get __gleam_prelude_variant__() {
      return "BitString";
    }

    inspect() {
      return `<<${Array.from(this.buffer).join(", ")}>>`;
    }

    get length() {
      return this.buffer.length;
    }

    byteAt(index) {
      return this.buffer[index];
    }

    floatAt(index) {
      return byteArrayToFloat$1(this.buffer.slice(index, index + 8));
    }

    intFromSlice(start, end) {
      return byteArrayToInt$1(this.buffer.slice(start, end));
    }

    binaryFromSlice(start, end) {
      return new BitString$1(this.buffer.slice(start, end));
    }

    sliceAfter(index) {
      return new BitString$1(this.buffer.slice(index));
    }
  };

  function toBitString$1(segments) {
    let size = (segment) =>
      segment instanceof Uint8Array ? segment.byteLength : 1;
    let bytes = segments.reduce((acc, segment) => acc + size(segment), 0);
    let view = new DataView(new ArrayBuffer(bytes));
    let cursor = 0;
    for (let segment of segments) {
      if (segment instanceof Uint8Array) {
        new Uint8Array(view.buffer).set(segment, cursor);
        cursor += segment.byteLength;
      } else {
        view.setInt8(cursor, segment);
        cursor++;
      }
    }
    return new BitString$1(new Uint8Array(view.buffer));
  }

  function byteArrayToInt$1(byteArray) {
    byteArray = byteArray.reverse();
    let value = 0;
    for (let i = byteArray.length - 1; i >= 0; i--) {
      value = value * 256 + byteArray[i];
    }
    return value;
  }

  function byteArrayToFloat$1(byteArray) {
    return new Float64Array(byteArray.reverse().buffer)[0];
  }

  function stringBits(string) {
    return new TextEncoder().encode(string);
  }

  let Result$4 = class Result extends CustomType$5 {
    static isResult(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "Ok" || variant === "Error";
    }
  };

  let Ok$3 = class Ok extends Result$4 {
    constructor(value) {
      super();
      this[0] = value;
    }

    get __gleam_prelude_variant__() {
      return "Ok";
    }

    isOk() {
      return true;
    }
  };

  let Error$4 = class Error extends Result$4 {
    constructor(detail) {
      super();
      this[0] = detail;
    }

    get __gleam_prelude_variant__() {
      return "Error";
    }

    isOk() {
      return false;
    }
  };

  function inspect$6(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$6).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$6).join(", ")}))`;
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
      return inspectObject$5(v);
    }
  }

  function inspectObject$5(v) {
    let [keys, get] = getters$5(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$6(k)}: ${inspect$6(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function isEqual$1(x, y) {
    let values = [x, y];

    while (values.length) {
      let a = values.pop();
      let b = values.pop();
      if (a === b) continue;

      if (!isObject$1(a) || !isObject$1(b)) return false;
      let unequal =
        !structurallyCompatibleObjects$1(a, b) ||
        unequalDates$1(a, b) ||
        unequalBuffers$1(a, b) ||
        unequalArrays$1(a, b) ||
        unequalMaps$1(a, b) ||
        unequalSets$1(a, b);
      if (unequal) return false;

      const proto = Object.getPrototypeOf(a);
      if (proto !== null && typeof proto.equals === "function") {
        try {
          if (a.equals(b)) continue;
          else return false;
        } catch {}
      }

      let [keys, get] = getters$5(a);
      for (let k of keys(a)) {
        values.push(get(a, k), get(b, k));
      }
    }

    return true;
  }

  function getters$5(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  function unequalDates$1(a, b) {
    return a instanceof Date && (a > b || a < b);
  }

  function unequalBuffers$1(a, b) {
    return (
      a.buffer instanceof ArrayBuffer &&
      a.BYTES_PER_ELEMENT &&
      !(a.byteLength === b.byteLength && a.every((n, i) => n === b[i]))
    );
  }

  function unequalArrays$1(a, b) {
    return Array.isArray(a) && a.length !== b.length;
  }

  function unequalMaps$1(a, b) {
    return a instanceof Map && a.size !== b.size;
  }

  function unequalSets$1(a, b) {
    return (
      a instanceof Set && (a.size != b.size || [...a].some((e) => !b.has(e)))
    );
  }

  function isObject$1(a) {
    return typeof a === "object" && a !== null;
  }

  function structurallyCompatibleObjects$1(a, b) {
    if (typeof a !== "object" && typeof b !== "object" && (!a || !b))
      return false;

    let nonstructural = [Promise, WeakSet, WeakMap, Function];
    if (nonstructural.some((c) => a instanceof c)) return false;

    return (
      a.constructor === b.constructor ||
      (a.__gleam_prelude_variant__ &&
        a.__gleam_prelude_variant__ === b.__gleam_prelude_variant__)
    );
  }

  function remainderInt(a, b) {
    if (b === 0) {
      return 0;
    } else {
      return a % b;
    }
  }

  function makeError$3(variant, module, line, fn, message, extra) {
    let error = new globalThis.Error(message);
    error.gleam_error = variant;
    error.module = module;
    error.line = line;
    error.fn = fn;
    for (let k in extra) error[k] = extra[k];
    return error;
  }

  class Some extends CustomType$5 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class None extends CustomType$5 {}

  function to_result(option, e) {
    if (option instanceof Some) {
      let a = option[0];
      return new Ok$3(a);
    } else {
      return new Error$4(e);
    }
  }

  function unwrap(option, default$) {
    if (option instanceof Some) {
      let x = option[0];
      return x;
    } else if (option instanceof None) {
      return default$;
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/option",
        140,
        "unwrap",
        "No case clause matched",
        { values: [option] }
      )
    }
  }

  class CompileError extends CustomType$5 {
    constructor(error, byte_index) {
      super();
      this.error = error;
      this.byte_index = byte_index;
    }
  }

  let Options$1 = class Options extends CustomType$5 {
    constructor(case_insensitive, multi_line) {
      super();
      this.case_insensitive = case_insensitive;
      this.multi_line = multi_line;
    }
  };

  function compile(pattern, options) {
    return compile_regex(pattern, options);
  }

  function from_string$2(pattern) {
    return compile(pattern, new Options$1(false, false));
  }

  function check(regex, content) {
    return regex_check(regex, content);
  }

  function absolute_value(x) {
    let $ = x >= 0;
    if ($) {
      return x;
    } else if (!$) {
      return x * -1;
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/int",
        19,
        "absolute_value",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function parse$1(string) {
    return parse_int(string);
  }

  function to_string$7(x) {
    return to_string$5(x);
  }

  function to_float(x) {
    return identity$1(x);
  }

  function min(a, b) {
    let $ = a < b;
    if ($) {
      return a;
    } else if (!$) {
      return b;
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/int",
        335,
        "min",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function random$1(min, max) {
    let _pipe = random(to_float(min), to_float(max));
    let _pipe$1 = floor(_pipe);
    return round(_pipe$1);
  }

  function size(map) {
    return map_size(map);
  }

  function to_list$2(map) {
    return map_to_list(map);
  }

  function new$$2() {
    return new_map();
  }

  function get(from, get) {
    return map_get(from, get);
  }

  function insert$1(map, key, value) {
    return map_insert(key, value, map);
  }

  function fold_list_of_pair(loop$list, loop$initial) {
    while (true) {
      let list = loop$list;
      let initial = loop$initial;
      if (list.hasLength(0)) {
        return initial;
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let rest = list.tail;
        loop$list = rest;
        loop$initial = insert$1(initial, x[0], x[1]);
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/map",
          85,
          "fold_list_of_pair",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function do_from_list(list) {
    return fold_list_of_pair(list, new$$2());
  }

  function from_list(list) {
    return do_from_list(list);
  }

  function reverse_and_concat(loop$remaining, loop$accumulator) {
    while (true) {
      let remaining = loop$remaining;
      let accumulator = loop$accumulator;
      if (remaining.hasLength(0)) {
        return accumulator;
      } else if (remaining.atLeastLength(1)) {
        let item = remaining.head;
        let rest = remaining.tail;
        loop$remaining = rest;
        loop$accumulator = toList$2([item], accumulator);
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/map",
          233,
          "reverse_and_concat",
          "No case clause matched",
          { values: [remaining] }
        )
      }
    }
  }

  function do_keys_acc(loop$list, loop$acc) {
    while (true) {
      let list = loop$list;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse_and_concat(acc, toList$2([]));
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        loop$list = xs;
        loop$acc = toList$2([x[0]], acc);
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/map",
          241,
          "do_keys_acc",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function do_keys(map) {
    let list_of_pairs = (() => {
      let _pipe = map;
      return to_list$2(_pipe);
    })();
    return do_keys_acc(list_of_pairs, toList$2([]));
  }

  function keys(map) {
    return do_keys(map);
  }

  function delete$$2(map, key) {
    return map_remove(key, map);
  }

  function drop$2(loop$map, loop$disallowed_keys) {
    while (true) {
      let map = loop$map;
      let disallowed_keys = loop$disallowed_keys;
      if (disallowed_keys.hasLength(0)) {
        return map;
      } else if (disallowed_keys.atLeastLength(1)) {
        let x = disallowed_keys.head;
        let xs = disallowed_keys.tail;
        loop$map = delete$$2(map, x);
        loop$disallowed_keys = xs;
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/map",
          463,
          "drop",
          "No case clause matched",
          { values: [disallowed_keys] }
        )
      }
    }
  }

  function do_fold$2(loop$list, loop$initial, loop$fun) {
    while (true) {
      let list = loop$list;
      let initial = loop$initial;
      let fun = loop$fun;
      if (list.hasLength(0)) {
        return initial;
      } else if (list.atLeastLength(1)) {
        let k = list.head[0];
        let v = list.head[1];
        let rest = list.tail;
        loop$list = rest;
        loop$initial = fun(initial, k, v);
        loop$fun = fun;
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/map",
          507,
          "do_fold",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function fold$5(map, initial, fun) {
    let _pipe = map;
    let _pipe$1 = to_list$2(_pipe);
    return do_fold$2(_pipe$1, initial, fun);
  }

  function do_map_values(f, map) {
    let f$1 = (map, k, v) => { return insert$1(map, k, f(k, v)); };
    let _pipe = map;
    return fold$5(_pipe, new$$2(), f$1);
  }

  function map_values(map, fun) {
    return do_map_values(fun, map);
  }

  function is_ok(result) {
    if (!result.isOk()) {
      return false;
    } else if (result.isOk()) {
      return true;
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/result",
        21,
        "is_ok",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function is_error$1(result) {
    if (result.isOk()) {
      return false;
    } else if (!result.isOk()) {
      return true;
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/result",
        42,
        "is_error",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function map$2(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return new Ok$3(fun(x));
    } else if (!result.isOk()) {
      let e = result[0];
      return new Error$4(e);
    } else {
      throw makeError$3(
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
      return new Ok$3(x);
    } else if (!result.isOk()) {
      let error = result[0];
      return new Error$4(fun(error));
    } else {
      throw makeError$3(
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
      return new Error$4(e);
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/result",
        163,
        "try",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function then$(result, fun) {
    return try$(result, fun);
  }

  function append_builder(builder, suffix) {
    return add$2(builder, suffix);
  }

  function from_strings(strings) {
    return concat$2(strings);
  }

  function from_string$1(string) {
    return identity$1(string);
  }

  function append$4(builder, second) {
    return append_builder(builder, from_string$1(second));
  }

  function to_string$6(builder) {
    return identity$1(builder);
  }

  function split$4(iodata, pattern) {
    return split$3(iodata, pattern);
  }

  function replace$3(builder, pattern, substitute) {
    return string_replace(builder, pattern, substitute);
  }

  class DecodeError extends CustomType$5 {
    constructor(expected, found, path) {
      super();
      this.expected = expected;
      this.found = found;
      this.path = path;
    }
  }

  function from(a) {
    return identity$1(a);
  }

  function string$3(data) {
    return decode_string(data);
  }

  function classify(data) {
    return classify_dynamic(data);
  }

  function int$1(data) {
    return decode_int(data);
  }

  function any$1(decoders) {
    return (data) => {
      if (decoders.hasLength(0)) {
        return new Error$4(
          toList$2([new DecodeError("another type", classify(data), toList$2([]))]),
        );
      } else if (decoders.atLeastLength(1)) {
        let decoder = decoders.head;
        let decoders$1 = decoders.tail;
        let $ = decoder(data);
        if ($.isOk()) {
          let decoded = $[0];
          return new Ok$3(decoded);
        } else if (!$.isOk()) {
          return any$1(decoders$1)(data);
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/dynamic",
            1009,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/dynamic",
          1002,
          "",
          "No case clause matched",
          { values: [decoders] }
        )
      }
    };
  }

  function all_errors(result) {
    if (result.isOk()) {
      return toList$2([]);
    } else if (!result.isOk()) {
      let errors = result[0];
      return errors;
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/dynamic",
        1487,
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
        return new Ok$3(constructor(a));
      } else {
        let a = $;
        return new Error$4(all_errors(a));
      }
    };
  }

  function push_path(error, name) {
    let name$1 = from(name);
    let decoder = any$1(
      toList$2([string$3, (x) => { return map$2(int$1(x), to_string$7); }]),
    );
    let name$2 = (() => {
      let $ = decoder(name$1);
      if ($.isOk()) {
        let name$2 = $[0];
        return name$2;
      } else if (!$.isOk()) {
        let _pipe = toList$2(["<", classify(name$1), ">"]);
        let _pipe$1 = from_strings(_pipe);
        return to_string$6(_pipe$1);
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/dynamic",
          593,
          "push_path",
          "No case clause matched",
          { values: [$] }
        )
      }
    })();
    return error.withFields({ path: toList$2([name$2], error.path) });
  }

  function map_errors(result, f) {
    return map_error(
      result,
      (_capture) => { return map$1(_capture, f); },
    );
  }

  function field$2(name, inner_type) {
    return (value) => {
      let missing_field_error = new DecodeError("field", "nothing", toList$2([]));
      return try$(
        decode_field(value, name),
        (maybe_inner) => {
          let _pipe = maybe_inner;
          let _pipe$1 = to_result(_pipe, toList$2([missing_field_error]));
          let _pipe$2 = try$(_pipe$1, inner_type);
          return map_errors(
            _pipe$2,
            (_capture) => { return push_path(_capture, name); },
          );
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
        return new Ok$3(constructor(a, b));
      } else {
        let a = $;
        let b = $1;
        return new Error$4(concat$1(toList$2([all_errors(a), all_errors(b)])));
      }
    };
  }

  function decode3(constructor, t1, t2, t3) {
    return (value) => {
      let $ = t1(value);
      let $1 = t2(value);
      let $2 = t3(value);
      if ($.isOk() && $1.isOk() && $2.isOk()) {
        let a = $[0];
        let b = $1[0];
        let c = $2[0];
        return new Ok$3(constructor(a, b, c));
      } else {
        let a = $;
        let b = $1;
        let c = $2;
        return new Error$4(
          concat$1(toList$2([all_errors(a), all_errors(b), all_errors(c)])),
        );
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
  function index(bitmap, bit) {
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
      if (isEqual$1(key, node.k)) {
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
    const idx = index(root.bitmap, bit);
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
      if (isEqual$1(key, nodeKey)) {
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
      if (isEqual$1(key, root.array[i].k)) {
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
    if (isEqual$1(key, node.k)) {
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
    const idx = index(root.bitmap, bit);
    const node = root.array[idx];
    if (node.type !== ENTRY) {
      return find(node, shift + SHIFT, hash, key);
    }
    if (isEqual$1(key, node.k)) {
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
      if (!isEqual$1(node.k, key)) {
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
    const idx = index(root.bitmap, bit);
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
    if (isEqual$1(key, node.k)) {
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
   * Extra wrapper to keep track of map size and clean up the API
   * @template K,V
   */
  class PMap {
    /**
     * @template V
     * @param {Record<string,V>} o
     * @returns {PMap<string,V>}
     */
    static fromObject(o) {
      const keys = Object.keys(o);
      /** @type PMap<string,V> */
      let m = PMap.new();
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        m = m.set(k, o[k]);
      }
      return m;
    }
    /**
     * @template K,V
     * @param {Map<K,V>} o
     * @returns {PMap<K,V>}
     */
    static fromMap(o) {
      /** @type PMap<K,V> */
      let m = PMap.new();
      o.forEach((v, k) => {
        m = m.set(k, v);
      });
      return m;
    }
    static new() {
      return new PMap(undefined, 0);
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
     * @returns {PMap<K,V>}
     */
    set(key, val) {
      const addedLeaf = { val: false };
      const root = this.root === undefined ? EMPTY : this.root;
      const newRoot = assoc(root, 0, getHash(key), key, val, addedLeaf);
      if (newRoot === this.root) {
        return this;
      }
      return new PMap(newRoot, addedLeaf.val ? this.size + 1 : this.size);
    }
    /**
     * @param {K} key
     * @returns {PMap<K,V>}
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
        return PMap.new();
      }
      return new PMap(newRoot, this.size - 1);
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
      if (!(o instanceof PMap)) {
        return false;
      }
      let equal = true;
      this.forEach((v, k) => {
        equal = equal && isEqual$1(o.get(k, !v), v);
      });
      return equal;
    }
  }

  const Nil = undefined;
  const NOT_FOUND = {};

  function identity$1(x) {
    return x;
  }

  function parse_int(value) {
    if (/^[-+]?(\d+)$/.test(value)) {
      return new Ok$3(parseInt(value));
    } else {
      return new Error$4(Nil);
    }
  }

  function to_string$5(term) {
    return term.toString();
  }

  function string_replace(string, target, substitute) {
    if (typeof string.replaceAll !== "undefined") {
      return string.replaceAll(target, substitute);
    }
    // Fallback for older Node.js versions:
    // 1. <https://stackoverflow.com/a/1144788>
    // 2. <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions#escaping>
    // TODO: This fallback could be remove once Node.js 14 is EOL
    // aka <https://nodejs.org/en/about/releases/> on or after 2024-04-30
    return string.replace(
      // $& means the whole matched string
      new RegExp(target.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"),
      substitute
    );
  }

  function string_length(string) {
    if (string === "") {
      return 0;
    }
    const iterator = graphemes_iterator(string);
    if (iterator) {
      let i = 0;
      for (const _ of iterator) {
        i++;
      }
      return i;
    } else {
      return string.match(/./gsu).length;
    }
  }

  function graphemes_iterator(string) {
    if (Intl && Intl.Segmenter) {
      return new Intl.Segmenter().segment(string)[Symbol.iterator]();
    }
  }

  function pop_grapheme$3(string) {
    let first;
    const iterator = graphemes_iterator(string);
    if (iterator) {
      first = iterator.next().value?.segment;
    } else {
      first = string.match(/./su)?.[0];
    }
    if (first) {
      return new Ok$3([first, string.slice(first.length)]);
    } else {
      return new Error$4(Nil);
    }
  }

  function lowercase$3(string) {
    return string.toLowerCase();
  }

  function uppercase$3(string) {
    return string.toUpperCase();
  }

  function add$2(a, b) {
    return a + b;
  }

  function split$3(xs, pattern) {
    return List$3.fromArray(xs.split(pattern));
  }

  function join$1(xs, separator) {
    const iterator = xs[Symbol.iterator]();
    let result = iterator.next().value || "";
    let current = iterator.next();
    while (!current.done) {
      result = result + separator + current.value;
      current = iterator.next();
    }
    return result;
  }

  function concat$2(xs) {
    let result = "";
    for (const x of xs) {
      result = result + x;
    }
    return result;
  }

  function length$4(data) {
    return data.length;
  }

  function starts_with$2(haystack, needle) {
    return haystack.startsWith(needle);
  }

  function split_once$2(haystack, needle) {
    const index = haystack.indexOf(needle);
    if (index >= 0) {
      const before = haystack.slice(0, index);
      const after = haystack.slice(index + needle.length);
      return new Ok$3([before, after]);
    } else {
      return new Error$4(Nil);
    }
  }

  function bit_string_from_string(string) {
    return toBitString$1([stringBits(string)]);
  }

  function print$2(string) {
    if (typeof process === "object") {
      process.stdout.write(string); // We can write without a trailing newline
    } else if (typeof Deno === "object") {
      Deno.stdout.writeSync(new TextEncoder().encode(string)); // We can write without a trailing newline
    } else {
      console.log(string); // We're in a browser. Newlines are mandated
    }
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

  function floor$1(float) {
    return Math.floor(float);
  }

  function round$1(float) {
    return Math.round(float);
  }

  function random_uniform() {
    const random_uniform_result = Math.random();
    // With round-to-nearest-even behavior, the ranges claimed for the functions below
    // (excluding the one for Math.random() itself) aren't exact.
    // If extremely large bounds are chosen (2^53 or higher),
    // it's possible in extremely rare cases to calculate the usually-excluded upper bound.
    // Note that as numbers in JavaScript are IEEE 754 floating point numbers
    // See: <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Math/random>
    // Because of this, we just loop 'until' we get a valid result where 0.0 <= x < 1.0:
    if (random_uniform_result === 1.0) {
      return random_uniform();
    }
    return random_uniform_result;
  }

  function regex_check(regex, string) {
    regex.lastIndex = 0;
    return regex.test(string);
  }

  function compile_regex(pattern, options) {
    try {
      let flags = "gu";
      if (options.case_insensitive) flags += "i";
      if (options.multi_line) flags += "m";
      return new Ok$3(new RegExp(pattern, flags));
    } catch (error) {
      const number = (error.columnNumber || 0) | 0;
      return new Error$4(new CompileError(error.message, number));
    }
  }

  function new_map() {
    return PMap.new();
  }

  function map_size(map) {
    return map.size;
  }

  function map_to_list(map) {
    return List$3.fromArray(map.entries());
  }

  function map_remove(key, map) {
    return map.delete(key);
  }

  function map_get(map, key) {
    const value = map.get(key, NOT_FOUND);
    if (value === NOT_FOUND) {
      return new Error$4(Nil);
    }
    return new Ok$3(value);
  }

  function map_insert(key, value, map) {
    return map.set(key, value);
  }

  // From https://developer.mozilla.org/en-US/docs/Glossary/Base64#Solution_2_%E2%80%93_rewrite_the_DOMs_atob()_and_btoa()_using_JavaScript's_TypedArrays_and_UTF-8
  function encode64$1(bit_string) {
    const aBytes = bit_string.buffer;
    let nMod3 = 2;
    let sB64Enc = "";

    for (let nLen = aBytes.length, nUint24 = 0, nIdx = 0; nIdx < nLen; nIdx++) {
      nMod3 = nIdx % 3;
      if (nIdx > 0 && ((nIdx * 4) / 3) % 76 === 0) {
        sB64Enc += "\r\n";
      }
      nUint24 |= aBytes[nIdx] << ((16 >>> nMod3) & 24);
      if (nMod3 === 2 || aBytes.length - nIdx === 1) {
        sB64Enc += String.fromCharCode(
          uint6ToB64((nUint24 >>> 18) & 63),
          uint6ToB64((nUint24 >>> 12) & 63),
          uint6ToB64((nUint24 >>> 6) & 63),
          uint6ToB64(nUint24 & 63)
        );
        nUint24 = 0;
      }
    }

    return (
      sB64Enc.substr(0, sB64Enc.length - 2 + nMod3) +
      (nMod3 === 2 ? "" : nMod3 === 1 ? "=" : "==")
    );
  }

  // From https://developer.mozilla.org/en-US/docs/Glossary/Base64#Solution_2_%E2%80%93_rewrite_the_DOMs_atob()_and_btoa()_using_JavaScript's_TypedArrays_and_UTF-8
  function uint6ToB64(nUint6) {
    return nUint6 < 26
      ? nUint6 + 65
      : nUint6 < 52
      ? nUint6 + 71
      : nUint6 < 62
      ? nUint6 - 4
      : nUint6 === 62
      ? 43
      : nUint6 === 63
      ? 47
      : 65;
  }

  // From https://developer.mozilla.org/en-US/docs/Glossary/Base64#Solution_2_%E2%80%93_rewrite_the_DOMs_atob()_and_btoa()_using_JavaScript's_TypedArrays_and_UTF-8
  function b64ToUint6(nChr) {
    return nChr > 64 && nChr < 91
      ? nChr - 65
      : nChr > 96 && nChr < 123
      ? nChr - 71
      : nChr > 47 && nChr < 58
      ? nChr + 4
      : nChr === 43
      ? 62
      : nChr === 47
      ? 63
      : 0;
  }

  // From https://developer.mozilla.org/en-US/docs/Glossary/Base64#Solution_2_%E2%80%93_rewrite_the_DOMs_atob()_and_btoa()_using_JavaScript's_TypedArrays_and_UTF-8
  function decode64$1(sBase64) {
    if (sBase64.match(/[^A-Za-z0-9\+\/=]/g)) return new Error$4(Nil);
    const sB64Enc = sBase64.replace(/=/g, "");
    const nInLen = sB64Enc.length;
    const nOutLen = (nInLen * 3 + 1) >> 2;
    const taBytes = new Uint8Array(nOutLen);

    for (
      let nMod3, nMod4, nUint24 = 0, nOutIdx = 0, nInIdx = 0;
      nInIdx < nInLen;
      nInIdx++
    ) {
      nMod4 = nInIdx & 3;
      nUint24 |= b64ToUint6(sB64Enc.charCodeAt(nInIdx)) << (6 * (3 - nMod4));
      if (nMod4 === 3 || nInLen - nInIdx === 1) {
        for (nMod3 = 0; nMod3 < 3 && nOutIdx < nOutLen; nMod3++, nOutIdx++) {
          taBytes[nOutIdx] = (nUint24 >>> ((16 >>> nMod3) & 24)) & 255;
        }
        nUint24 = 0;
      }
    }

    return new Ok$3(new BitString$1(taBytes));
  }

  function classify_dynamic(data) {
    if (typeof data === "string") {
      return "String";
    } else if (Result$4.isResult(data)) {
      return "Result";
    } else if (List$3.isList(data)) {
      return "List";
    } else if (Number.isInteger(data)) {
      return "Int";
    } else if (Array.isArray(data)) {
      return `Tuple of ${data.length} elements`;
    } else if (BitString$1.isBitString(data)) {
      return "BitString";
    } else if (data instanceof PMap) {
      return "Map";
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
    return new Error$4(
      List$3.fromArray([new DecodeError(expected, got, List$3.fromArray([]))])
    );
  }

  function decode_string(data) {
    return typeof data === "string"
      ? new Ok$3(data)
      : decoder_error("String", data);
  }

  function decode_int(data) {
    return Number.isInteger(data) ? new Ok$3(data) : decoder_error("Int", data);
  }

  function decode_field(value, name) {
    const not_a_map_error = () => decoder_error("Map", value);

    if (
      value instanceof PMap ||
      value instanceof WeakMap ||
      value instanceof Map
    ) {
      const entry = map_get(value, name);
      return new Ok$3(entry.isOk() ? new Some(entry[0]) : new None());
    } else if (Object.getPrototypeOf(value) == Object.prototype) {
      return try_get_field(value, name, () => new Ok$3(new None()));
    } else {
      return try_get_field(value, name, not_a_map_error);
    }
  }

  function try_get_field(value, field, or_else) {
    try {
      return field in value ? new Ok$3(new Some(value[field])) : or_else();
    } catch {
      return or_else();
    }
  }

  function floor(x) {
    return floor$1(x);
  }

  function negate(x) {
    return -1.0 * x;
  }

  function do_round(x) {
    let $ = x >= 0.0;
    if ($) {
      return round$1(x);
    } else {
      return 0 - round$1(negate(x));
    }
  }

  function round(x) {
    return do_round(x);
  }

  function random(min, max) {
    return (random_uniform() * (max - min)) + min;
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

  function do_length$1(list) {
    return do_length_acc(list, 0);
  }

  function length$3(list) {
    return do_length$1(list);
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
        loop$accumulator = toList$2([item], accumulator);
      } else {
        throw makeError$3(
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
    return do_reverse_acc(list, toList$2([]));
  }

  function reverse(xs) {
    return do_reverse(xs);
  }

  function contains$1(loop$list, loop$elem) {
    while (true) {
      let list = loop$list;
      let elem = loop$elem;
      if (list.hasLength(0)) {
        return false;
      } else if (list.atLeastLength(1) && isEqual$1(list.head, elem)) {
        list.head;
        return true;
      } else if (list.atLeastLength(1)) {
        let rest$1 = list.tail;
        loop$list = rest$1;
        loop$elem = elem;
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          188,
          "contains",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function first(list) {
    if (list.hasLength(0)) {
      return new Error$4(undefined);
    } else if (list.atLeastLength(1)) {
      let x = list.head;
      return new Ok$3(x);
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/list",
        215,
        "first",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  function do_filter(loop$list, loop$fun, loop$acc) {
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
          if ($) {
            return toList$2([x], acc);
          } else if (!$) {
            return acc;
          } else {
            throw makeError$3(
              "case_no_match",
              "gleam/list",
              296,
              "do_filter",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        loop$list = xs;
        loop$fun = fun;
        loop$acc = new_acc;
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          293,
          "do_filter",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function filter(list, predicate) {
    return do_filter(list, predicate, toList$2([]));
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
            return toList$2([x$1], acc);
          } else if (!$.isOk()) {
            return acc;
          } else {
            throw makeError$3(
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
        throw makeError$3(
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
    return do_filter_map(list, fun, toList$2([]));
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
        loop$acc = toList$2([fun(x)], acc);
      } else {
        throw makeError$3(
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
    return do_map(list, fun, toList$2([]));
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
        let acc$1 = toList$2([fun(index, x)], acc);
        loop$list = xs;
        loop$fun = fun;
        loop$index = index + 1;
        loop$acc = acc$1;
      } else {
        throw makeError$3(
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
    return do_index_map(list, fun, 0, toList$2([]));
  }

  function do_try_map(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return new Ok$3(reverse(acc));
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let $ = fun(x);
        if ($.isOk()) {
          let y = $[0];
          loop$list = xs;
          loop$fun = fun;
          loop$acc = toList$2([y], acc);
        } else if (!$.isOk()) {
          let error = $[0];
          return new Error$4(error);
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/list",
            483,
            "do_try_map",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError$3(
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
    return do_try_map(list, fun, toList$2([]));
  }

  function drop$1(loop$list, loop$n) {
    while (true) {
      let list = loop$list;
      let n = loop$n;
      let $ = n <= 0;
      if ($) {
        return list;
      } else if (!$) {
        if (list.hasLength(0)) {
          return toList$2([]);
        } else if (list.atLeastLength(1)) {
          let xs = list.tail;
          loop$list = xs;
          loop$n = n - 1;
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/list",
            553,
            "drop",
            "No case clause matched",
            { values: [list] }
          )
        }
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          550,
          "drop",
          "No case clause matched",
          { values: [$] }
        )
      }
    }
  }

  function do_take$1(loop$list, loop$n, loop$acc) {
    while (true) {
      let list = loop$list;
      let n = loop$n;
      let acc = loop$acc;
      let $ = n <= 0;
      if ($) {
        return reverse(acc);
      } else if (!$) {
        if (list.hasLength(0)) {
          return reverse(acc);
        } else if (list.atLeastLength(1)) {
          let x = list.head;
          let xs = list.tail;
          loop$list = xs;
          loop$n = n - 1;
          loop$acc = toList$2([x], acc);
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/list",
            564,
            "do_take",
            "No case clause matched",
            { values: [list] }
          )
        }
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          561,
          "do_take",
          "No case clause matched",
          { values: [$] }
        )
      }
    }
  }

  function take$1(list, n) {
    return do_take$1(list, n, toList$2([]));
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
        loop$second = toList$2([item], second);
      } else {
        throw makeError$3(
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

  function do_append$1(first, second) {
    return do_append_acc(reverse(first), second);
  }

  function append$3(first, second) {
    return do_append$1(first, second);
  }

  function prepend(list, item) {
    return toList$2([item], list);
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
        loop$suffix = toList$2([first$1], suffix);
      } else {
        throw makeError$3(
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
        throw makeError$3(
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

  function concat$1(lists) {
    return do_concat(lists, toList$2([]));
  }

  function flatten(lists) {
    return do_concat(lists, toList$2([]));
  }

  function fold$4(loop$list, loop$initial, loop$fun) {
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
        throw makeError$3(
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

  function fold_right(list, initial, fun) {
    if (list.hasLength(0)) {
      return initial;
    } else if (list.atLeastLength(1)) {
      let x = list.head;
      let rest$1 = list.tail;
      return fun(fold_right(rest$1, initial, fun), x);
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/list",
        748,
        "fold_right",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  function find_map(loop$haystack, loop$fun) {
    while (true) {
      let haystack = loop$haystack;
      let fun = loop$fun;
      if (haystack.hasLength(0)) {
        return new Error$4(undefined);
      } else if (haystack.atLeastLength(1)) {
        let x = haystack.head;
        let rest$1 = haystack.tail;
        let $ = fun(x);
        if ($.isOk()) {
          let x$1 = $[0];
          return new Ok$3(x$1);
        } else {
          loop$haystack = rest$1;
          loop$fun = fun;
        }
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          917,
          "find_map",
          "No case clause matched",
          { values: [haystack] }
        )
      }
    }
  }

  function do_intersperse(loop$list, loop$separator, loop$acc) {
    while (true) {
      let list = loop$list;
      let separator = loop$separator;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let rest$1 = list.tail;
        loop$list = rest$1;
        loop$separator = separator;
        loop$acc = toList$2([x, separator], acc);
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          1096,
          "do_intersperse",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function intersperse(list, elem) {
    if (list.hasLength(0)) {
      return list;
    } else if (list.hasLength(1)) {
      return list;
    } else if (list.atLeastLength(1)) {
      let x = list.head;
      let rest$1 = list.tail;
      return do_intersperse(rest$1, elem, toList$2([x]));
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/list",
        1119,
        "intersperse",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  function at$1(list, index) {
    let $ = index >= 0;
    if ($) {
      let _pipe = list;
      let _pipe$1 = drop$1(_pipe, index);
      return first(_pipe$1);
    } else if (!$) {
      return new Error$4(undefined);
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/list",
        1144,
        "at",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function key_find(keyword_list, desired_key) {
    return find_map(
      keyword_list,
      (keyword) => {
        let key = keyword[0];
        let value = keyword[1];
        let $ = isEqual$1(key, desired_key);
        if ($) {
          return new Ok$3(value);
        } else if (!$) {
          return new Error$4(undefined);
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/list",
            1443,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      },
    );
  }

  function do_pop_map(loop$haystack, loop$mapper, loop$checked) {
    while (true) {
      let haystack = loop$haystack;
      let mapper = loop$mapper;
      let checked = loop$checked;
      if (haystack.hasLength(0)) {
        return new Error$4(undefined);
      } else if (haystack.atLeastLength(1)) {
        let x = haystack.head;
        let rest$1 = haystack.tail;
        let $ = mapper(x);
        if ($.isOk()) {
          let y = $[0];
          return new Ok$3([y, append$3(reverse(checked), rest$1)]);
        } else if (!$.isOk()) {
          loop$haystack = rest$1;
          loop$mapper = mapper;
          loop$checked = toList$2([x], checked);
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/list",
            1494,
            "do_pop_map",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/list",
          1491,
          "do_pop_map",
          "No case clause matched",
          { values: [haystack] }
        )
      }
    }
  }

  function pop_map(haystack, is_desired) {
    return do_pop_map(haystack, is_desired, toList$2([]));
  }

  function key_pop(haystack, key) {
    return pop_map(
      haystack,
      (entry) => {
        let k = entry[0];
        let v = entry[1];
        if (isEqual$1(k, key)) {
          return new Ok$3(v);
        } else {
          return new Error$4(undefined);
        }
      },
    );
  }

  function key_set(list, key, value) {
    if (list.hasLength(0)) {
      return toList$2([[key, value]]);
    } else if (list.atLeastLength(1) && isEqual$1(list.head[0], key)) {
      list.head[0];
      let rest$1 = list.tail;
      return toList$2([[key, value]], rest$1);
    } else if (list.atLeastLength(1)) {
      let first$1 = list.head;
      let rest$1 = list.tail;
      return toList$2([first$1], key_set(rest$1, key, value));
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/list",
        1587,
        "key_set",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  class Stop extends CustomType$5 {}

  class Continue extends CustomType$5 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  class Iterator extends CustomType$5 {
    constructor(continuation) {
      super();
      this.continuation = continuation;
    }
  }

  class Next extends CustomType$5 {
    constructor(element, accumulator) {
      super();
      this.element = element;
      this.accumulator = accumulator;
    }
  }

  let Done$2 = class Done extends CustomType$5 {};

  function do_unfold(initial, f) {
    return () => {
      let $ = f(initial);
      if ($ instanceof Next) {
        let x = $.element;
        let acc = $.accumulator;
        return new Continue(x, do_unfold(acc, f));
      } else if ($ instanceof Done$2) {
        return new Stop();
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/iterator",
          48,
          "",
          "No case clause matched",
          { values: [$] }
        )
      }
    };
  }

  function unfold(initial, f) {
    let _pipe = initial;
    let _pipe$1 = do_unfold(_pipe, f);
    return new Iterator(_pipe$1);
  }

  function repeatedly(f) {
    return unfold(undefined, (_) => { return new Next(f(), undefined); });
  }

  function repeat$1(x) {
    return repeatedly(() => { return x; });
  }

  function do_fold$1(loop$continuation, loop$f, loop$accumulator) {
    while (true) {
      let continuation = loop$continuation;
      let f = loop$f;
      let accumulator = loop$accumulator;
      let $ = continuation();
      if ($ instanceof Continue) {
        let elem = $[0];
        let next = $[1];
        loop$continuation = next;
        loop$f = f;
        loop$accumulator = f(accumulator, elem);
      } else if ($ instanceof Stop) {
        return accumulator;
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/iterator",
          177,
          "do_fold",
          "No case clause matched",
          { values: [$] }
        )
      }
    }
  }

  function fold$3(iterator, initial, f) {
    let _pipe = iterator.continuation;
    return do_fold$1(_pipe, f, initial);
  }

  function to_list$1(iterator) {
    let _pipe = iterator;
    let _pipe$1 = fold$3(
      _pipe,
      toList$2([]),
      (acc, e) => { return toList$2([e], acc); },
    );
    return reverse(_pipe$1);
  }

  function do_take(continuation, desired) {
    return () => {
      let $ = desired > 0;
      if (!$) {
        return new Stop();
      } else if ($) {
        let $1 = continuation();
        if ($1 instanceof Stop) {
          return new Stop();
        } else if ($1 instanceof Continue) {
          let e = $1[0];
          let next = $1[1];
          return new Continue(e, do_take(next, desired - 1));
        } else {
          throw makeError$3(
            "case_no_match",
            "gleam/iterator",
            277,
            "",
            "No case clause matched",
            { values: [$1] }
          )
        }
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/iterator",
          274,
          "",
          "No case clause matched",
          { values: [$] }
        )
      }
    };
  }

  function take(iterator, desired) {
    let _pipe = iterator.continuation;
    let _pipe$1 = do_take(_pipe, desired);
    return new Iterator(_pipe$1);
  }

  function length$2(string) {
    return string_length(string);
  }

  function replace$2(string, pattern, substitute) {
    let _pipe = string;
    let _pipe$1 = from_string$1(_pipe);
    let _pipe$2 = replace$3(_pipe$1, pattern, substitute);
    return to_string$6(_pipe$2);
  }

  function lowercase$2(string) {
    return lowercase$3(string);
  }

  function uppercase$2(string) {
    return uppercase$3(string);
  }

  function starts_with$1(string, prefix) {
    return starts_with$2(string, prefix);
  }

  function split_once$1(x, substring) {
    return split_once$2(x, substring);
  }

  function append$2(first, second) {
    let _pipe = first;
    let _pipe$1 = from_string$1(_pipe);
    let _pipe$2 = append$4(_pipe$1, second);
    return to_string$6(_pipe$2);
  }

  function concat(strings) {
    let _pipe = strings;
    let _pipe$1 = from_strings(_pipe);
    return to_string$6(_pipe$1);
  }

  function repeat(string, times) {
    let _pipe = repeat$1(string);
    let _pipe$1 = take(_pipe, times);
    let _pipe$2 = to_list$1(_pipe$1);
    return concat(_pipe$2);
  }

  function join(strings, separator) {
    return join$1(strings, separator);
  }

  function pop_grapheme$2(string) {
    return pop_grapheme$3(string);
  }

  function do_to_graphemes(loop$string, loop$acc) {
    while (true) {
      let string = loop$string;
      let acc = loop$acc;
      let $ = pop_grapheme$2(string);
      if ($.isOk()) {
        let grapheme = $[0][0];
        let rest = $[0][1];
        loop$string = rest;
        loop$acc = toList$2([grapheme], acc);
      } else {
        return acc;
      }
    }
  }

  function to_graphemes(string) {
    let _pipe = do_to_graphemes(string, toList$2([]));
    return reverse(_pipe);
  }

  function split$2(x, substring) {
    if (substring === "") {
      return to_graphemes(x);
    } else {
      let _pipe = x;
      let _pipe$1 = from_string$1(_pipe);
      let _pipe$2 = split$4(_pipe$1, substring);
      return map$1(_pipe$2, to_string$6);
    }
  }

  function inspect$5(term) {
    let _pipe = inspect$6(term);
    return to_string$6(_pipe);
  }

  class Uri extends CustomType$5 {
    constructor(scheme, userinfo, host, port, path, query, fragment) {
      super();
      this.scheme = scheme;
      this.userinfo = userinfo;
      this.host = host;
      this.port = port;
      this.path = path;
      this.query = query;
      this.fragment = fragment;
    }
  }

  function to_string$4(uri) {
    let parts = (() => {
      let $ = uri.fragment;
      if ($ instanceof Some) {
        let fragment = $[0];
        return toList$2(["#", fragment]);
      } else {
        return toList$2([]);
      }
    })();
    let parts$1 = (() => {
      let $ = uri.query;
      if ($ instanceof Some) {
        let query = $[0];
        return toList$2(["?", query], parts);
      } else {
        return parts;
      }
    })();
    let parts$2 = toList$2([uri.path], parts$1);
    let parts$3 = (() => {
      let $ = uri.host;
      let $1 = starts_with$1(uri.path, "/");
      if ($ instanceof Some && !$1 && $[0] !== "") {
        $[0];
        return toList$2(["/"], parts$2);
      } else {
        return parts$2;
      }
    })();
    let parts$4 = (() => {
      let $ = uri.host;
      let $1 = uri.port;
      if ($ instanceof Some && $1 instanceof Some) {
        let port = $1[0];
        return toList$2([":", to_string$7(port)], parts$3);
      } else {
        return parts$3;
      }
    })();
    let parts$5 = (() => {
      let $ = uri.scheme;
      let $1 = uri.userinfo;
      let $2 = uri.host;
      if ($ instanceof Some && $1 instanceof Some && $2 instanceof Some) {
        let s = $[0];
        let u = $1[0];
        let h = $2[0];
        return toList$2([s, "://", u, "@", h], parts$4);
      } else if ($ instanceof Some && $1 instanceof None && $2 instanceof Some) {
        let s = $[0];
        let h = $2[0];
        return toList$2([s, "://", h], parts$4);
      } else if ($ instanceof Some && $1 instanceof Some && $2 instanceof None) {
        let s = $[0];
        return toList$2([s, ":"], parts$4);
      } else if ($ instanceof Some && $1 instanceof None && $2 instanceof None) {
        let s = $[0];
        return toList$2([s, ":"], parts$4);
      } else if ($ instanceof None && $1 instanceof None && $2 instanceof Some) {
        let h = $2[0];
        return toList$2(["//", h], parts$4);
      } else if ($ instanceof None && $1 instanceof Some && $2 instanceof None) {
        return parts$4;
      } else if ($ instanceof None && $1 instanceof None && $2 instanceof None) {
        return parts$4;
      } else {
        throw makeError$3(
          "case_no_match",
          "gleam/uri",
          349,
          "to_string",
          "No case clause matched",
          { values: [$, $1, $2] }
        )
      }
    })();
    return concat(parts$5);
  }

  let CustomType$4 = class CustomType {
    inspect() {
      let field = (label) => {
        let value = inspect$4(this[label]);
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
  };

  let List$2 = class List {
    static fromArray(array, tail) {
      let t = tail || new Empty$4();
      return array.reduceRight((xs, x) => new NonEmpty$2(x, xs), t);
    }

    static isList(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "EmptyList" || variant === "NonEmptyList";
    }

    [Symbol.iterator]() {
      return new ListIterator$2(this);
    }

    inspect() {
      return `[${this.toArray().map(inspect$4).join(", ")}]`;
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
  };

  function toList$1(elements, tail) {
    return List$2.fromArray(elements, tail);
  }

  let ListIterator$2 = class ListIterator {
    #current;

    constructor(current) {
      this.#current = current;
    }

    next() {
      if (this.#current.isEmpty()) {
        return { done: true };
      } else {
        let { head, tail } = this.#current;
        this.#current = tail;
        return { value: head, done: false };
      }
    }
  };

  let Empty$4 = class Empty extends List$2 {
    get __gleam_prelude_variant__() {
      return "EmptyList";
    }

    isEmpty() {
      return true;
    }
  };

  let NonEmpty$2 = class NonEmpty extends List$2 {
    constructor(head, tail) {
      super();
      this.head = head;
      this.tail = tail;
    }

    get __gleam_prelude_variant__() {
      return "NonEmptyList";
    }

    isEmpty() {
      return false;
    }
  };

  function inspect$4(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$4).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$4).join(", ")}))`;
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
      return inspectObject$4(v);
    }
  }

  function inspectObject$4(v) {
    let [keys, get] = getters$4(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$4(k)}: ${inspect$4(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function getters$4(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  function makeError$2(variant, module, line, fn, message, extra) {
    let error = new globalThis.Error(message);
    error.gleam_error = variant;
    error.module = module;
    error.line = line;
    error.fn = fn;
    for (let k in extra) error[k] = extra[k];
    return error;
  }

  function from_string(x) {
    return bit_string_from_string(x);
  }

  function byte_size(x) {
    return length$4(x);
  }

  class Get extends CustomType$4 {}

  class Post extends CustomType$4 {}

  class Head extends CustomType$4 {}

  class Put extends CustomType$4 {}

  class Delete extends CustomType$4 {}

  class Trace extends CustomType$4 {}

  class Connect extends CustomType$4 {}

  class Options extends CustomType$4 {}

  class Patch extends CustomType$4 {}

  class Other extends CustomType$4 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Http extends CustomType$4 {}

  class Https extends CustomType$4 {}

  function method_to_string(method) {
    if (method instanceof Connect) {
      return "connect";
    } else if (method instanceof Delete) {
      return "delete";
    } else if (method instanceof Get) {
      return "get";
    } else if (method instanceof Head) {
      return "head";
    } else if (method instanceof Options) {
      return "options";
    } else if (method instanceof Patch) {
      return "patch";
    } else if (method instanceof Post) {
      return "post";
    } else if (method instanceof Put) {
      return "put";
    } else if (method instanceof Trace) {
      return "trace";
    } else if (method instanceof Other) {
      let s = method[0];
      return s;
    } else {
      throw makeError$2(
        "case_no_match",
        "gleam/http",
        50,
        "method_to_string",
        "No case clause matched",
        { values: [method] }
      )
    }
  }

  function scheme_to_string(scheme) {
    if (scheme instanceof Http) {
      return "http";
    } else if (scheme instanceof Https) {
      return "https";
    } else {
      throw makeError$2(
        "case_no_match",
        "gleam/http",
        82,
        "scheme_to_string",
        "No case clause matched",
        { values: [scheme] }
      )
    }
  }

  class Request extends CustomType$4 {
    constructor(method, headers, body, scheme, host, port, path, query) {
      super();
      this.method = method;
      this.headers = headers;
      this.body = body;
      this.scheme = scheme;
      this.host = host;
      this.port = port;
      this.path = path;
      this.query = query;
    }
  }

  function to_uri(request) {
    return new Uri(
      new Some(scheme_to_string(request.scheme)),
      new None(),
      new Some(request.host),
      request.port,
      request.path,
      request.query,
      new None(),
    );
  }

  function set_header(request, key, value) {
    let headers = key_set(request.headers, lowercase$2(key), value);
    return request.withFields({ headers: headers });
  }

  function set_body(req, body) {
    if (!(req instanceof Request)) {
      throw makeError$2(
        "assignment_no_match",
        "gleam/http/request",
        102,
        "set_body",
        "Assignment pattern did not match",
        { value: req }
      )
    }
    let method = req.method;
    let headers = req.headers;
    let scheme = req.scheme;
    let host = req.host;
    let port = req.port;
    let path = req.path;
    let query = req.query;
    return new Request(method, headers, body, scheme, host, port, path, query);
  }

  function set_method(req, method) {
    return req.withFields({ method: method });
  }

  function new$$1() {
    return new Request(
      new Get(),
      toList$1([]),
      "",
      new Https(),
      "localhost",
      new None(),
      "",
      new None(),
    );
  }

  function set_scheme(req, scheme) {
    return req.withFields({ scheme: scheme });
  }

  function set_host(req, host) {
    return req.withFields({ host: host });
  }

  function set_path(req, path) {
    return req.withFields({ path: path });
  }

  class Response extends CustomType$4 {
    constructor(status, headers, body) {
      super();
      this.status = status;
      this.headers = headers;
      this.body = body;
    }
  }

  let CustomType$3 = class CustomType {
    inspect() {
      let field = (label) => {
        let value = inspect$3(this[label]);
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
  };

  let Result$3 = class Result extends CustomType$3 {
    static isResult(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "Ok" || variant === "Error";
    }
  };

  let Error$3 = class Error extends Result$3 {
    constructor(detail) {
      super();
      this[0] = detail;
    }

    get __gleam_prelude_variant__() {
      return "Error";
    }

    isOk() {
      return false;
    }
  };

  function inspect$3(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$3).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$3).join(", ")}))`;
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
      return inspectObject$3(v);
    }
  }

  function inspectObject$3(v) {
    let [keys, get] = getters$3(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$3(k)}: ${inspect$3(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function getters$3(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  function makeError$1(variant, module, line, fn, message, extra) {
    let error = new globalThis.Error(message);
    error.gleam_error = variant;
    error.module = module;
    error.line = line;
    error.fn = fn;
    for (let k in extra) error[k] = extra[k];
    return error;
  }

  function update_reference(ref, f) {
    let value = dereference(ref);
    set_reference(ref, f(value));
    return value;
  }

  function toArray(list) {
    return list.toArray();
  }

  function map(thing, fn) {
    return thing.map(fn);
  }

  // A wrapper around a promise to prevent `Promise<Promise<T>>` collapsing into
  // `Promise<T>`.
  class PromiseLayer {
    constructor(promise) {
      this.promise = promise;
    }

    static wrap(value) {
      return value instanceof Promise ? new PromiseLayer(value) : value;
    }

    static unwrap(value) {
      return value instanceof PromiseLayer ? value.promise : value;
    }
  }

  function newPromise(executor) {
    return new Promise((resolve) =>
      executor((value) => {
        resolve(PromiseLayer.wrap(value));
      })
    );
  }

  function resolve$1(value) {
    return Promise.resolve(PromiseLayer.wrap(value));
  }

  function then(promise, fn) {
    return promise.then((value) => fn(PromiseLayer.unwrap(value)));
  }

  function map_promise(promise, fn) {
    return promise.then((value) =>
      PromiseLayer.wrap(fn(PromiseLayer.unwrap(value)))
    );
  }

  class Reference {
    constructor(value) {
      this.value = value;
    }
  }

  function dereference(reference) {
    return reference.value;
  }

  function make_reference(value) {
    return new Reference(value);
  }

  function set_reference(ref, value) {
    let previous = ref.value;
    ref.value = value;
    return previous;
  }

  function map_try(promise, callback) {
    let _pipe = promise;
    return map_promise(
      _pipe,
      (result) => {
        if (result.isOk()) {
          let a = result[0];
          return callback(a);
        } else if (!result.isOk()) {
          let e = result[0];
          return new Error$3(e);
        } else {
          throw makeError$1(
            "case_no_match",
            "gleam/javascript/promise",
            37,
            "",
            "No case clause matched",
            { values: [result] }
          )
        }
      },
    );
  }

  function try_await(promise, callback) {
    let _pipe = promise;
    return then(
      _pipe,
      (result) => {
        if (result.isOk()) {
          let a = result[0];
          return callback(a);
        } else if (!result.isOk()) {
          let e = result[0];
          return resolve$1(new Error$3(e));
        } else {
          throw makeError$1(
            "case_no_match",
            "gleam/javascript/promise",
            50,
            "",
            "No case clause matched",
            { values: [result] }
          )
        }
      },
    );
  }

  let CustomType$2 = class CustomType {
    inspect() {
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
  };

  let List$1 = class List {
    static fromArray(array, tail) {
      let t = tail || new Empty$3();
      return array.reduceRight((xs, x) => new NonEmpty$1(x, xs), t);
    }

    static isList(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "EmptyList" || variant === "NonEmptyList";
    }

    [Symbol.iterator]() {
      return new ListIterator$1(this);
    }

    inspect() {
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
  };

  let ListIterator$1 = class ListIterator {
    #current;

    constructor(current) {
      this.#current = current;
    }

    next() {
      if (this.#current.isEmpty()) {
        return { done: true };
      } else {
        let { head, tail } = this.#current;
        this.#current = tail;
        return { value: head, done: false };
      }
    }
  };

  let Empty$3 = class Empty extends List$1 {
    get __gleam_prelude_variant__() {
      return "EmptyList";
    }

    isEmpty() {
      return true;
    }
  };

  let NonEmpty$1 = class NonEmpty extends List$1 {
    constructor(head, tail) {
      super();
      this.head = head;
      this.tail = tail;
    }

    get __gleam_prelude_variant__() {
      return "NonEmptyList";
    }

    isEmpty() {
      return false;
    }
  };

  let Result$2 = class Result extends CustomType$2 {
    static isResult(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "Ok" || variant === "Error";
    }
  };

  let Ok$2 = class Ok extends Result$2 {
    constructor(value) {
      super();
      this[0] = value;
    }

    get __gleam_prelude_variant__() {
      return "Ok";
    }

    isOk() {
      return true;
    }
  };

  let Error$2 = class Error extends Result$2 {
    constructor(detail) {
      super();
      this[0] = detail;
    }

    get __gleam_prelude_variant__() {
      return "Error";
    }

    isOk() {
      return false;
    }
  };

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
      return inspectObject$2(v);
    }
  }

  function inspectObject$2(v) {
    let [keys, get] = getters$2(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$2(k)}: ${inspect$2(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function getters$2(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  async function raw_send(request) {
    try {
      return new Ok$2(await fetch(request));
    } catch (error) {
      return new Error$2(new NetworkError(error.toString()));
    }
  }

  function from_fetch_response(response) {
    return new Response(
      response.status,
      List$1.fromArray([...response.headers]),
      response
    );
  }

  function to_fetch_request(request) {
    let url = to_string$4(to_uri(request));
    let method = method_to_string(request.method).toUpperCase();
    let options = {
      headers: make_headers(request.headers),
      method,
    };
    if (method !== "GET" && method !== "HEAD") options.body = request.body;
    return new globalThis.Request(url, options);
  }

  function make_headers(headersList) {
    let headers = new globalThis.Headers();
    for (let [k, v] of headersList) headers.append(k.toLowerCase(), v);
    return headers;
  }

  async function read_text_body(response) {
    let body;
    try {
      body = await response.body.text();
    } catch (error) {
      return new Error$2(new UnableToReadBody());
    }
    return new Ok$2(response.withFields({ body }));
  }

  class NetworkError extends CustomType$2 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class UnableToReadBody extends CustomType$2 {}

  function send(request) {
    let _pipe = request;
    let _pipe$1 = to_fetch_request(_pipe);
    let _pipe$2 = raw_send(_pipe$1);
    return try_await(
      _pipe$2,
      (resp) => { return resolve$1(new Ok$2(from_fetch_response(resp))); },
    );
  }

  function print$1(string) {
    return print$2(string);
  }

  function debug$2(term) {
    let _pipe = term;
    let _pipe$1 = inspect$5(_pipe);
    print_debug(_pipe$1);
    return term;
  }

  let Set$1 = class Set extends CustomType$5 {
    constructor(map) {
      super();
      this.map = map;
    }
  };

  const token = undefined;

  function new$() {
    return new Set$1(new$$2());
  }

  function insert(set, member) {
    return new Set$1(insert$1(set.map, member, token));
  }

  function contains(set, member) {
    let _pipe = set.map;
    let _pipe$1 = get(_pipe, member);
    return is_ok(_pipe$1);
  }

  function delete$$1(set, member) {
    return new Set$1(delete$$2(set.map, member));
  }

  function to_list(set) {
    return keys(set.map);
  }

  function fold$2(set, initial, reducer) {
    return fold$5(set.map, initial, (a, k, _) => { return reducer(a, k); });
  }

  function drop(set, disallowed) {
    return fold$4(disallowed, set, delete$$1);
  }

  function order(first, second) {
    let $ = size(first.map) > size(second.map);
    if ($) {
      return [first, second];
    } else if (!$) {
      return [second, first];
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/set",
        225,
        "order",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function union(first, second) {
    let $ = order(first, second);
    let larger = $[0];
    let smaller = $[1];
    return fold$2(smaller, larger, insert);
  }

  let CustomType$1 = class CustomType {
    inspect() {
      let field = (label) => {
        let value = inspect$1(this[label]);
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
  };

  class List {
    static fromArray(array, tail) {
      let t = tail || new Empty$2();
      return array.reduceRight((xs, x) => new NonEmpty(x, xs), t);
    }

    static isList(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "EmptyList" || variant === "NonEmptyList";
    }

    [Symbol.iterator]() {
      return new ListIterator(this);
    }

    inspect() {
      return `[${this.toArray().map(inspect$1).join(", ")}]`;
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
      if (this.#current.isEmpty()) {
        return { done: true };
      } else {
        let { head, tail } = this.#current;
        this.#current = tail;
        return { value: head, done: false };
      }
    }
  }

  let Empty$2 = class Empty extends List {
    get __gleam_prelude_variant__() {
      return "EmptyList";
    }

    isEmpty() {
      return true;
    }
  };

  class NonEmpty extends List {
    constructor(head, tail) {
      super();
      this.head = head;
      this.tail = tail;
    }

    get __gleam_prelude_variant__() {
      return "NonEmptyList";
    }

    isEmpty() {
      return false;
    }
  }

  class BitString {
    static isBitString(data) {
      return data?.__gleam_prelude_variant__ === "BitString";
    }

    constructor(buffer) {
      this.buffer = buffer;
    }

    get __gleam_prelude_variant__() {
      return "BitString";
    }

    inspect() {
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
      return new BitString(this.buffer.slice(start, end));
    }

    sliceAfter(index) {
      return new BitString(this.buffer.slice(index));
    }
  }

  function toBitString(segments) {
    let size = (segment) =>
      segment instanceof Uint8Array ? segment.byteLength : 1;
    let bytes = segments.reduce((acc, segment) => acc + size(segment), 0);
    let view = new DataView(new ArrayBuffer(bytes));
    let cursor = 0;
    for (let segment of segments) {
      if (segment instanceof Uint8Array) {
        new Uint8Array(view.buffer).set(segment, cursor);
        cursor += segment.byteLength;
      } else {
        view.setInt8(cursor, segment);
        cursor++;
      }
    }
    return new BitString(new Uint8Array(view.buffer));
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

  let Result$1 = class Result extends CustomType$1 {
    static isResult(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "Ok" || variant === "Error";
    }
  };

  let Ok$1 = class Ok extends Result$1 {
    constructor(value) {
      super();
      this[0] = value;
    }

    get __gleam_prelude_variant__() {
      return "Ok";
    }

    isOk() {
      return true;
    }
  };

  let Error$1 = class Error extends Result$1 {
    constructor(detail) {
      super();
      this[0] = detail;
    }

    get __gleam_prelude_variant__() {
      return "Error";
    }

    isOk() {
      return false;
    }
  };

  function inspect$1(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$1).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$1).join(", ")}))`;
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
    let [keys, get] = getters$1(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$1(k)}: ${inspect$1(get(v, k))}`);
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

      let [keys, get] = getters$1(a);
      for (let k of keys(a)) {
        values.push(get(a, k), get(b, k));
      }
    }

    return true;
  }

  function getters$1(object) {
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

    return (
      a.constructor === b.constructor ||
      (a.__gleam_prelude_variant__ &&
        a.__gleam_prelude_variant__ === b.__gleam_prelude_variant__)
    );
  }

  function divideInt(a, b) {
    return Math.trunc(divideFloat(a, b));
  }

  function divideFloat(a, b) {
    if (b === 0) {
      return 0;
    } else {
      return a / b;
    }
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

  function singleton(value) {
    let _pipe = new$();
    return insert(_pipe, value);
  }

  class Var extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  let Fun$1 = class Fun extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  };

  let Binary$3 = class Binary extends CustomType$1 {};

  let Integer$4 = class Integer extends CustomType$1 {};

  let String$2 = class String extends CustomType$1 {};

  let LinkedList$2 = class LinkedList extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  };

  let Record$2 = class Record extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  };

  let Union$1 = class Union extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  };

  let Empty$1 = class Empty extends CustomType$1 {};

  class RowExtend extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  class EffectExtend extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  const unit$3 = new Record$2(new Empty$1());

  const boolean$1 = new Union$1(
    new RowExtend("True", unit$3, new RowExtend("False", unit$3, new Empty$1())),
  );

  function ftv$3(loop$type_) {
    while (true) {
      let type_ = loop$type_;
      if (type_ instanceof Var) {
        let a = type_[0];
        return singleton(a);
      } else if (type_ instanceof Fun$1) {
        let from = type_[0];
        let effects = type_[1];
        let to = type_[2];
        return union(union(ftv$3(from), ftv$3(effects)), ftv$3(to));
      } else if (type_ instanceof Binary$3) {
        return new$();
      } else if (type_ instanceof Integer$4) {
        return new$();
      } else if (type_ instanceof String$2) {
        return new$();
      } else if (type_ instanceof LinkedList$2) {
        let element = type_[0];
        loop$type_ = element;
      } else if (type_ instanceof Record$2) {
        let row = type_[0];
        loop$type_ = row;
      } else if (type_ instanceof Union$1) {
        let row = type_[0];
        loop$type_ = row;
      } else if (type_ instanceof Empty$1) {
        return new$();
      } else if (type_ instanceof RowExtend) {
        let value = type_[1];
        let rest = type_[2];
        return union(ftv$3(value), ftv$3(rest));
      } else if (type_ instanceof EffectExtend) {
        let lift = type_[1][0];
        let reply = type_[1][1];
        let rest = type_[2];
        return union(union(ftv$3(lift), ftv$3(reply)), ftv$3(rest));
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/jm/type_",
          24,
          "ftv",
          "No case clause matched",
          { values: [type_] }
        )
      }
    }
  }

  function apply$3(loop$s, loop$type_) {
    while (true) {
      let s = loop$s;
      let type_ = loop$type_;
      if (type_ instanceof Var) {
        let a = type_[0];
        let $ = get(s, a);
        if ($.isOk()) {
          let new$ = $[0];
          loop$s = s;
          loop$type_ = new$;
        } else if (!$.isOk() && !$[0]) {
          return type_;
        } else {
          throw makeError(
            "case_no_match",
            "eyg/analysis/jm/type_",
            43,
            "apply",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else if (type_ instanceof Fun$1) {
        let from = type_[0];
        let effects = type_[1];
        let to = type_[2];
        return new Fun$1(apply$3(s, from), apply$3(s, effects), apply$3(s, to));
      } else if (type_ instanceof Binary$3) {
        return type_;
      } else if (type_ instanceof Integer$4) {
        return type_;
      } else if (type_ instanceof String$2) {
        return type_;
      } else if (type_ instanceof LinkedList$2) {
        let element = type_[0];
        return new LinkedList$2(apply$3(s, element));
      } else if (type_ instanceof Record$2) {
        let row = type_[0];
        return new Record$2(apply$3(s, row));
      } else if (type_ instanceof Union$1) {
        let row = type_[0];
        return new Union$1(apply$3(s, row));
      } else if (type_ instanceof Empty$1) {
        return type_;
      } else if (type_ instanceof RowExtend) {
        let label = type_[0];
        let value = type_[1];
        let rest = type_[2];
        return new RowExtend(label, apply$3(s, value), apply$3(s, rest));
      } else if (type_ instanceof EffectExtend) {
        let label = type_[0];
        let lift = type_[1][0];
        let reply = type_[1][1];
        let rest = type_[2];
        return new EffectExtend(
          label,
          [apply$3(s, lift), apply$3(s, reply)],
          apply$3(s, rest),
        );
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/jm/type_",
          40,
          "apply",
          "No case clause matched",
          { values: [type_] }
        )
      }
    }
  }

  function resolve(loop$t, loop$s) {
    while (true) {
      let t = loop$t;
      let s = loop$s;
      if (t instanceof Var) {
        let a = t[0];
        let $ = get(s, a);
        if ($.isOk()) {
          let u = $[0];
          loop$t = u;
          loop$s = s;
        } else if (!$.isOk() && !$[0]) {
          return t;
        } else {
          throw makeError(
            "case_no_match",
            "eyg/analysis/jm/type_",
            67,
            "resolve",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else if (t instanceof Fun$1) {
        let u = t[0];
        let v = t[1];
        let w = t[2];
        return new Fun$1(resolve(u, s), resolve(v, s), resolve(w, s));
      } else if (t instanceof Binary$3) {
        return t;
      } else if (t instanceof String$2) {
        return t;
      } else if (t instanceof Integer$4) {
        return t;
      } else if (t instanceof Empty$1) {
        return t;
      } else if (t instanceof LinkedList$2) {
        let element = t[0];
        return new LinkedList$2(resolve(element, s));
      } else if (t instanceof Record$2) {
        let u = t[0];
        return new Record$2(resolve(u, s));
      } else if (t instanceof Union$1) {
        let u = t[0];
        return new Union$1(resolve(u, s));
      } else if (t instanceof RowExtend) {
        let label = t[0];
        let u = t[1];
        let v = t[2];
        return new RowExtend(label, resolve(u, s), resolve(v, s));
      } else if (t instanceof EffectExtend) {
        let label = t[0];
        let u = t[1][0];
        let v = t[1][1];
        let w = t[2];
        return new EffectExtend(
          label,
          [resolve(u, s), resolve(v, s)],
          resolve(w, s),
        );
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/jm/type_",
          62,
          "resolve",
          "No case clause matched",
          { values: [t] }
        )
      }
    }
  }

  function fresh(next) {
    return [new Var(next), next + 1];
  }

  function tail(next) {
    let $ = fresh(next);
    let item = $[0];
    let next$1 = $[1];
    return [new LinkedList$2(item), next$1];
  }

  function cons$1(next) {
    let $ = fresh(next);
    let item = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let e1 = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let e2 = $2[0];
    let next$3 = $2[1];
    let t = new Fun$1(
      item,
      e1,
      new Fun$1(new LinkedList$2(item), e2, new LinkedList$2(item)),
    );
    return [t, next$3];
  }

  function empty$1(next) {
    return [new Record$2(new Empty$1()), next];
  }

  function extend$5(label, next) {
    let $ = fresh(next);
    let value = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let rest = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let e1 = $2[0];
    let next$3 = $2[1];
    let $3 = fresh(next$3);
    let e2 = $3[0];
    let next$4 = $3[1];
    let t = new Fun$1(
      value,
      e1,
      new Fun$1(new Record$2(rest), e2, new Record$2(new RowExtend(label, value, rest))),
    );
    return [t, next$4];
  }

  function select$2(label, next) {
    let $ = fresh(next);
    let value = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let rest = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let e = $2[0];
    let next$3 = $2[1];
    let t = new Fun$1(new Record$2(new RowExtend(label, value, rest)), e, value);
    return [t, next$3];
  }

  function overwrite$2(label, next) {
    let $ = fresh(next);
    let new$ = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let old = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let rest = $2[0];
    let next$3 = $2[1];
    let $3 = fresh(next$3);
    let e1 = $3[0];
    let next$4 = $3[1];
    let $4 = fresh(next$4);
    let e2 = $4[0];
    let next$5 = $4[1];
    let t = new Fun$1(
      new$,
      e1,
      new Fun$1(
        new Record$2(new RowExtend(label, old, rest)),
        e2,
        new Record$2(new RowExtend(label, new$, rest)),
      ),
    );
    return [t, next$5];
  }

  function tag$1(label, next) {
    let $ = fresh(next);
    let value = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let rest = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let e = $2[0];
    let next$3 = $2[1];
    let t = new Fun$1(value, e, new Union$1(new RowExtend(label, value, rest)));
    return [t, next$3];
  }

  function case_(label, next) {
    let $ = fresh(next);
    let value = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let ret = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let rest = $2[0];
    let next$3 = $2[1];
    let $3 = fresh(next$3);
    let e1 = $3[0];
    let next$4 = $3[1];
    let $4 = fresh(next$4);
    let e2 = $4[0];
    let next$5 = $4[1];
    let $5 = fresh(next$5);
    let e3 = $5[0];
    let next$6 = $5[1];
    let $6 = fresh(next$6);
    let e4 = $6[0];
    let next$7 = $6[1];
    let $7 = fresh(next$7);
    let e5 = $7[0];
    let next$8 = $7[1];
    let branch = new Fun$1(value, e1, ret);
    let else$ = new Fun$1(new Union$1(rest), e2, ret);
    let exec = new Fun$1(new Union$1(new RowExtend(label, value, rest)), e3, ret);
    let t = new Fun$1(branch, e4, new Fun$1(else$, e5, exec));
    return [t, next$8];
  }

  function nocases$1(next) {
    let $ = fresh(next);
    let ret = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let e = $1[0];
    let next$2 = $1[1];
    let t = new Fun$1(new Union$1(new Empty$1()), e, ret);
    return [t, next$2];
  }

  function perform$2(label, next) {
    let $ = fresh(next);
    let arg = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let ret = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let tail$1 = $2[0];
    let next$3 = $2[1];
    let t = new Fun$1(arg, new EffectExtend(label, [arg, ret], tail$1), ret);
    return [t, next$3];
  }

  function handle$2(label, next) {
    let $ = fresh(next);
    let ret = $[0];
    let next$1 = $[1];
    let $1 = fresh(next$1);
    let lift = $1[0];
    let next$2 = $1[1];
    let $2 = fresh(next$2);
    let reply = $2[0];
    let next$3 = $2[1];
    let $3 = fresh(next$3);
    let tail$1 = $3[0];
    let next$4 = $3[1];
    let $4 = fresh(next$4);
    let e = $4[0];
    let next$5 = $4[1];
    let kont = new Fun$1(reply, tail$1, ret);
    let handler = new Fun$1(lift, tail$1, new Fun$1(kont, tail$1, ret));
    let exec = new Fun$1(unit$3, new EffectExtend(label, [lift, reply], tail$1), ret);
    let t = new Fun$1(handler, e, new Fun$1(exec, tail$1, ret));
    return [t, next$5];
  }

  function result$1(value, reason) {
    return new Union$1(
      new RowExtend("Ok", value, new RowExtend("Error", reason, new Empty$1())),
    );
  }

  class MissingVariable extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class TypeMismatch extends CustomType$1 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  class RowMismatch extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class InvalidTail extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class RecursiveType extends CustomType$1 {}

  function render_row(r) {
    if (r instanceof Empty$1) {
      return toList([]);
    } else if (r instanceof Var) {
      let i = r[0];
      return toList([append$2("..", to_string$7(i))]);
    } else if (r instanceof RowExtend) {
      let label = r[0];
      let value = r[1];
      let tail = r[2];
      let field = concat(toList([label, ": ", render_type(value)]));
      return toList([field], render_row(tail));
    } else {
      return toList(["not a valid row"]);
    }
  }

  function render_type(typ) {
    if (typ instanceof Var) {
      let i = typ[0];
      return to_string$7(i);
    } else if (typ instanceof Integer$4) {
      return "Integer";
    } else if (typ instanceof String$2) {
      return "String";
    } else if (typ instanceof LinkedList$2) {
      let el = typ[0];
      return concat(toList(["List(", render_type(el), ")"]));
    } else if (typ instanceof Fun$1) {
      let from = typ[0];
      let effects = typ[1];
      let to = typ[2];
      return concat(
        toList([
          "(",
          render_type(from),
          ") ->",
          render_effects(effects),
          " ",
          render_type(to),
        ]),
      );
    } else if (typ instanceof Union$1) {
      let row = typ[0];
      return concat(
        toList([
          "[",
          concat(
            (() => {
              let _pipe = render_row(row);
              return intersperse(_pipe, " | ");
            })(),
          ),
          "]",
        ]),
      );
    } else if (typ instanceof Record$2) {
      let row = typ[0];
      return concat(
        toList([
          "{",
          concat(
            (() => {
              let _pipe = render_row(row);
              return intersperse(_pipe, ", ");
            })(),
          ),
          "}",
        ]),
      );
    } else if (typ instanceof EffectExtend) {
      return concat(toList(["<", render_effects(typ), ">"]));
    } else {
      let row = typ;
      return concat(
        toList([
          "{",
          (() => {
            let _pipe = render_row(row);
            return join(_pipe, "");
          })(),
          "}",
        ]),
      );
    }
  }

  function render_failure(reason, _, _1) {
    if (reason instanceof TypeMismatch) {
      let a = reason[0];
      let b = reason[1];
      return concat(
        toList(["Type Missmatch: ", render_type(a), " vs ", render_type(b)]),
      );
    } else if (reason instanceof RowMismatch) {
      let label = reason[0];
      return append$2("Row Missmatch: ", label);
    } else if (reason instanceof MissingVariable) {
      let x = reason[0];
      return append$2("missing variable: ", x);
    } else if (reason instanceof RecursiveType) {
      return "Recursive type";
    } else if (reason instanceof InvalidTail) {
      return "invalid tail";
    } else {
      throw makeError(
        "case_no_match",
        "atelier/view/type_",
        9,
        "render_failure",
        "No case clause matched",
        { values: [reason] }
      )
    }
  }

  function render_effect(label, lift, resume) {
    return concat(
      toList([label, "(", render_type(lift), ", ", render_type(resume), ")"]),
    );
  }

  function collect_effect(loop$eff, loop$acc) {
    while (true) {
      let eff = loop$eff;
      let acc = loop$acc;
      if (eff instanceof EffectExtend) {
        let label = eff[0];
        let lift = eff[1][0];
        let resume = eff[1][1];
        let tail = eff[2];
        loop$eff = tail;
        loop$acc = toList([render_effect(label, lift, resume)], acc);
      } else {
        return acc;
      }
    }
  }

  function render_effects(effects) {
    if (effects instanceof Var) {
      return "";
    } else if (effects instanceof Empty$1) {
      return "";
    } else if (effects instanceof EffectExtend) {
      let label = effects[0];
      let lift = effects[1][0];
      let resume = effects[1][1];
      let tail = effects[2];
      return concat(
        toList([
          " <",
          join(
            collect_effect(tail, toList([render_effect(label, lift, resume)])),
            ", ",
          ),
          ">",
        ]),
      );
    } else {
      return "not a valid effect";
    }
  }

  class Location extends CustomType$1 {
    constructor(path, selection, always) {
      super();
      this.path = path;
      this.selection = selection;
      this.always = always;
    }
  }

  function open(location) {
    if (!(location instanceof Location)) {
      throw makeError(
        "assignment_no_match",
        "easel/location",
        11,
        "open",
        "Assignment pattern did not match",
        { value: location }
      )
    }
    let selection = location.selection;
    if (selection instanceof None) {
      return location.always;
    } else if (selection instanceof Some) {
      return true;
    } else {
      throw makeError(
        "case_no_match",
        "easel/location",
        12,
        "open",
        "No case clause matched",
        { values: [selection] }
      )
    }
  }

  function child$1(location, i) {
    if (!(location instanceof Location)) {
      throw makeError(
        "assignment_no_match",
        "easel/location",
        28,
        "child",
        "Assignment pattern did not match",
        { value: location }
      )
    }
    let path = location.path;
    let selection = location.selection;
    let path$1 = append$3(path, toList([i]));
    let selection$1 = (() => {
      if (selection instanceof Some &&
      selection[0].atLeastLength(1) &&
      i === selection[0].head) {
        selection[0].head;
        let inner = selection[0].tail;
        return new Some(inner);
      } else {
        return new None();
      }
    })();
    return location.withFields({ path: path$1, selection: selection$1 });
  }

  function ftv$2(scheme) {
    let forall = scheme[0];
    let typ = scheme[1];
    return drop(ftv$3(typ), forall);
  }

  function apply$2(sub, scheme) {
    let forall = scheme[0];
    let typ = scheme[1];
    return [forall, apply$3(drop$2(sub, forall), typ)];
  }

  function ftv_for_key(state, _, scheme) {
    return union(state, ftv$2(scheme));
  }

  function ftv$1(env) {
    return fold$5(env, new$(), ftv_for_key);
  }

  function apply$1(sub, env) {
    return map_values(
      env,
      (_, scheme) => { return apply$2(sub, scheme); },
    );
  }

  function rewrite_row(new_label, row, s, next) {
    if (row instanceof Empty$1) {
      return new Error$1(new RowMismatch(new_label));
    } else if (row instanceof RowExtend && row[0] === new_label) {
      row[0];
      let value = row[1];
      let tail = row[2];
      return new Ok$1([value, tail, s, next]);
    } else if (row instanceof Var) {
      let a = row[0];
      let $ = fresh(next);
      let value = $[0];
      let next$1 = $[1];
      let $1 = fresh(next$1);
      let tail = $1[0];
      let next$2 = $1[1];
      let s$1 = insert$1(s, a, new RowExtend(new_label, value, tail));
      return new Ok$1([value, tail, s$1, next$2]);
    } else if (row instanceof RowExtend) {
      let label = row[0];
      let value = row[1];
      let tail = row[2];
      return then$(
        rewrite_row(new_label, tail, s, next),
        (_use0) => {
          let value_new = _use0[0];
          let tail_new = _use0[1];
          let s$1 = _use0[2];
          let next$1 = _use0[3];
          return new Ok$1(
            [value_new, new RowExtend(label, value, tail_new), s$1, next$1],
          );
        },
      );
    } else {
      return new Error$1(new InvalidTail(row));
    }
  }

  function rewrite_effect(new_label, effect, s, next) {
    if (effect instanceof Empty$1) {
      return new Error$1(new RowMismatch(new_label));
    } else if (effect instanceof EffectExtend && effect[0] === new_label) {
      effect[0];
      let lift = effect[1][0];
      let reply = effect[1][1];
      let tail = effect[2];
      return new Ok$1([lift, reply, tail, s, next]);
    } else if (effect instanceof Var) {
      let a = effect[0];
      let $ = fresh(next);
      let lift = $[0];
      let next$1 = $[1];
      let $1 = fresh(next$1);
      let reply = $1[0];
      let next$2 = $1[1];
      let $2 = fresh(next$2);
      let tail = $2[0];
      let next$3 = $2[1];
      let s$1 = insert$1(
        s,
        a,
        new EffectExtend(new_label, [lift, reply], tail),
      );
      return new Ok$1([lift, reply, tail, s$1, next$3]);
    } else if (effect instanceof EffectExtend) {
      let label = effect[0];
      let field = effect[1];
      let tail = effect[2];
      return then$(
        rewrite_effect(new_label, tail, s, next),
        (_use0) => {
          let lift_new = _use0[0];
          let reply_new = _use0[1];
          let tail_new = _use0[2];
          let s$1 = _use0[3];
          let next$1 = _use0[4];
          return new Ok$1(
            [
              lift_new,
              reply_new,
              new EffectExtend(label, field, tail_new),
              s$1,
              next$1,
            ],
          );
        },
      );
    } else {
      return new Error$1(new InvalidTail(effect));
    }
  }

  function do_unify(loop$constraints, loop$s, loop$next) {
    while (true) {
      let constraints = loop$constraints;
      let s = loop$s;
      let next = loop$next;
      if (constraints.hasLength(0)) {
        return new Ok$1([s, next]);
      } else if (constraints.atLeastLength(1)) {
        let t1 = constraints.head[0];
        let t2 = constraints.head[1];
        let rest = constraints.tail;
        let $ = apply$3(s, t1);
        let $1 = apply$3(s, t2);
        if ($ instanceof Var && $1 instanceof Var && $[0] === $1[0]) {
          $[0];
          $1[0];
          loop$constraints = rest;
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof Var) {
          let i = $[0];
          let t1$1 = $1;
          let $2 = contains(ftv$3(t1$1), i);
          if ($2) {
            return new Error$1(new RecursiveType());
          } else if (!$2) {
            loop$constraints = rest;
            loop$s = insert$1(s, i, t1$1);
            loop$next = next;
          } else {
            throw makeError(
              "case_no_match",
              "eyg/analysis/jm/unify",
              23,
              "do_unify",
              "No case clause matched",
              { values: [$2] }
            )
          }
        } else if ($1 instanceof Var) {
          let t1$1 = $;
          let i = $1[0];
          let $2 = contains(ftv$3(t1$1), i);
          if ($2) {
            return new Error$1(new RecursiveType());
          } else if (!$2) {
            loop$constraints = rest;
            loop$s = insert$1(s, i, t1$1);
            loop$next = next;
          } else {
            throw makeError(
              "case_no_match",
              "eyg/analysis/jm/unify",
              23,
              "do_unify",
              "No case clause matched",
              { values: [$2] }
            )
          }
        } else if ($ instanceof Fun$1 && $1 instanceof Fun$1) {
          let a1 = $[0];
          let e1 = $[1];
          let r1 = $[2];
          let a2 = $1[0];
          let e2 = $1[1];
          let r2 = $1[2];
          loop$constraints = toList([[a1, a2], [e1, e2], [r1, r2]], rest);
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof Integer$4 && $1 instanceof Integer$4) {
          loop$constraints = rest;
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof String$2 && $1 instanceof String$2) {
          loop$constraints = rest;
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof LinkedList$2 && $1 instanceof LinkedList$2) {
          let i1 = $[0];
          let i2 = $1[0];
          loop$constraints = toList([[i1, i2]], rest);
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof Record$2 && $1 instanceof Record$2) {
          let r1 = $[0];
          let r2 = $1[0];
          loop$constraints = toList([[r1, r2]], rest);
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof Union$1 && $1 instanceof Union$1) {
          let r1 = $[0];
          let r2 = $1[0];
          loop$constraints = toList([[r1, r2]], rest);
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof Empty$1 && $1 instanceof Empty$1) {
          loop$constraints = rest;
          loop$s = s;
          loop$next = next;
        } else if ($ instanceof RowExtend && $1 instanceof RowExtend) {
          let label1 = $[0];
          let value1 = $[1];
          let tail1 = $[2];
          let row2 = $1;
          return then$(
            rewrite_row(label1, row2, s, next),
            (_use0) => {
              let value2 = _use0[0];
              let tail2 = _use0[1];
              let s1 = _use0[2];
              let next$1 = _use0[3];
              let s$1 = s1;
              return do_unify(
                toList([[value1, value2], [tail1, tail2]], rest),
                s$1,
                next$1,
              );
            },
          );
        } else if ($ instanceof EffectExtend && $1 instanceof EffectExtend) {
          let label1 = $[0];
          let lift1 = $[1][0];
          let reply1 = $[1][1];
          let tail1 = $[2];
          let row2 = $1;
          return then$(
            rewrite_effect(label1, row2, s, next),
            (_use0) => {
              let lift2 = _use0[0];
              let reply2 = _use0[1];
              let tail2 = _use0[2];
              let s$1 = _use0[3];
              let next$1 = _use0[4];
              return do_unify(
                toList([[lift1, lift2], [reply1, reply2], [tail1, tail2]], rest),
                s$1,
                next$1,
              );
            },
          );
        } else {
          let t1$1 = $;
          let t2$1 = $1;
          return new Error$1(new TypeMismatch(t1$1, t2$1));
        }
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/jm/unify",
          17,
          "do_unify",
          "No case clause matched",
          { values: [constraints] }
        )
      }
    }
  }

  function unify(t1, t2, s, next) {
    return do_unify(toList([[t1, t2]]), s, next);
  }

  function mono(type_) {
    return [toList([]), type_];
  }

  function generalise(sub, env, t) {
    let env$1 = apply$1(sub, env);
    let t$1 = apply$3(sub, t);
    let forall = drop(ftv$3(t$1), to_list(ftv$1(env$1)));
    return [to_list(forall), t$1];
  }

  function apply_once(s, type_) {
    if (type_ instanceof Var) {
      let a = type_[0];
      let $ = get(s, a);
      if ($.isOk()) {
        let new$ = $[0];
        return new$;
      } else if (!$.isOk() && !$[0]) {
        return type_;
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/jm/infer",
          39,
          "apply_once",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else if (type_ instanceof Fun$1) {
      let from = type_[0];
      let effects = type_[1];
      let to = type_[2];
      return new Fun$1(
        apply_once(s, from),
        apply_once(s, effects),
        apply_once(s, to),
      );
    } else if (type_ instanceof Binary$3) {
      return type_;
    } else if (type_ instanceof Integer$4) {
      return type_;
    } else if (type_ instanceof String$2) {
      return type_;
    } else if (type_ instanceof LinkedList$2) {
      let element = type_[0];
      return new LinkedList$2(apply_once(s, element));
    } else if (type_ instanceof Record$2) {
      let row = type_[0];
      return new Record$2(apply_once(s, row));
    } else if (type_ instanceof Union$1) {
      let row = type_[0];
      return new Union$1(apply_once(s, row));
    } else if (type_ instanceof Empty$1) {
      return type_;
    } else if (type_ instanceof RowExtend) {
      let label = type_[0];
      let value = type_[1];
      let rest = type_[2];
      return new RowExtend(label, apply_once(s, value), apply_once(s, rest));
    } else if (type_ instanceof EffectExtend) {
      let label = type_[0];
      let lift = type_[1][0];
      let reply = type_[1][1];
      let rest = type_[2];
      return new EffectExtend(
        label,
        [apply_once(s, lift), apply_once(s, reply)],
        apply_once(s, rest),
      );
    } else {
      throw makeError(
        "case_no_match",
        "eyg/analysis/jm/infer",
        36,
        "apply_once",
        "No case clause matched",
        { values: [type_] }
      )
    }
  }

  function instantiate(scheme, next) {
    let next$1 = next + 1000;
    let forall = scheme[0];
    let type_ = scheme[1];
    let s = (() => {
      let _pipe = index_map(
        forall,
        (i, old) => { return [old, new Var(next$1 + i)]; },
      );
      return from_list(_pipe);
    })();
    let next$2 = next$1 + length$3(forall);
    let type_$1 = apply_once(s, type_);
    return [type_$1, next$2];
  }

  function extend$4(env, label, scheme) {
    return insert$1(env, label, scheme);
  }

  function unify_at$1(type_, found, sub, next, types, ref) {
    let $ = unify(type_, found, sub, next);
    if ($.isOk()) {
      let s = $[0][0];
      let next$1 = $[0][1];
      return [s, next$1, insert$1(types, ref, new Ok$1(type_))];
    } else if (!$.isOk()) {
      let reason = $[0];
      return [
        sub,
        next,
        insert$1(types, ref, new Error$1([reason, type_, found])),
      ];
    } else {
      throw makeError(
        "case_no_match",
        "eyg/analysis/jm/infer",
        66,
        "unify_at",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function extend_b(env, key, t) {
    let scheme = generalise(new$$2(), new$$2(), t);
    return extend$4(env, key, scheme);
  }

  function equal$1() {
    return new Fun$1(
      new Var(0),
      new Var(1),
      new Fun$1(new Var(0), new Var(2), boolean$1),
    );
  }

  function debug$1() {
    return new Fun$1(new Var(0), new Var(1), new String$2());
  }

  function fix$1() {
    return new Fun$1(
      new Fun$1(new Var(0), new Var(1), new Var(0)),
      new Var(2),
      new Var(0),
    );
  }

  function eval$$2() {
    return new Fun$1(new Var(0), new Var(1), new Var(2));
  }

  function serialize$1() {
    return new Fun$1(new Var(0), new Var(1), new String$2());
  }

  function capture$2() {
    return new Fun$1(new Var(0), new Var(1), new Var(2));
  }

  function encode_uri$1() {
    return new Fun$1(new String$2(), new Var(1), new String$2());
  }

  function add$1() {
    return new Fun$1(
      new Integer$4(),
      new Var(0),
      new Fun$1(new Integer$4(), new Var(1), new Integer$4()),
    );
  }

  function subtract$1() {
    return new Fun$1(
      new Integer$4(),
      new Var(0),
      new Fun$1(new Integer$4(), new Var(1), new Integer$4()),
    );
  }

  function multiply$1() {
    return new Fun$1(
      new Integer$4(),
      new Var(0),
      new Fun$1(new Integer$4(), new Var(1), new Integer$4()),
    );
  }

  function divide$1() {
    return new Fun$1(
      new Integer$4(),
      new Var(0),
      new Fun$1(new Integer$4(), new Var(1), new Integer$4()),
    );
  }

  function absolute$1() {
    return new Fun$1(new Integer$4(), new Var(0), new Integer$4());
  }

  function to_string$3() {
    return new Fun$1(new Integer$4(), new Var(0), new String$2());
  }

  function append$1() {
    return new Fun$1(
      new String$2(),
      new Var(0),
      new Fun$1(new String$2(), new Var(1), new String$2()),
    );
  }

  function replace$1() {
    return new Fun$1(
      new String$2(),
      new Var(0),
      new Fun$1(
        new String$2(),
        new Var(1),
        new Fun$1(new String$2(), new Var(2), new String$2()),
      ),
    );
  }

  function split$1() {
    return new Fun$1(
      new String$2(),
      new Var(0),
      new Fun$1(
        new String$2(),
        new Var(1),
        new Record$2(
          new RowExtend(
            "head",
            new String$2(),
            new RowExtend(
              "tail",
              new LinkedList$2(new String$2()),
              new Empty$1(),
            ),
          ),
        ),
      ),
    );
  }

  function uppercase$1() {
    return new Fun$1(new String$2(), new Var(0), new String$2());
  }

  function lowercase$1() {
    return new Fun$1(new String$2(), new Var(0), new String$2());
  }

  function length$1() {
    return new Fun$1(new String$2(), new Var(0), new Integer$4());
  }

  function pop_grapheme$1() {
    let parts = new Record$2(
      new RowExtend(
        "head",
        new String$2(),
        new RowExtend("tail", new String$2(), new Empty$1()),
      ),
    );
    return new Fun$1(new String$2(), new Var(0), result$1(parts, unit$3));
  }

  function pop$2() {
    let parts = new Record$2(
      new RowExtend(
        "head",
        new Var(0),
        new RowExtend("tail", new LinkedList$2(new Var(0)), new Empty$1()),
      ),
    );
    return new Fun$1(
      new LinkedList$2(new Var(0)),
      new Var(1),
      result$1(parts, unit$3),
    );
  }

  function fold$1() {
    let item = new Var(0);
    let eff1 = new Var(1);
    let acc = new Var(2);
    let eff2 = new Var(3);
    let eff3 = new Var(4);
    let eff4 = new Var(5);
    let eff5 = new Var(6);
    return new Fun$1(
      new LinkedList$2(item),
      eff1,
      new Fun$1(
        acc,
        eff2,
        new Fun$1(new Fun$1(item, eff3, new Fun$1(acc, eff4, acc)), eff5, acc),
      ),
    );
  }

  function builtins() {
    let _pipe = new$$2();
    let _pipe$1 = extend_b(_pipe, "equal", equal$1());
    let _pipe$2 = extend_b(_pipe$1, "debug", debug$1());
    let _pipe$3 = extend_b(_pipe$2, "fix", fix$1());
    let _pipe$4 = extend_b(_pipe$3, "eval", eval$$2());
    let _pipe$5 = extend_b(_pipe$4, "serialize", serialize$1());
    let _pipe$6 = extend_b(_pipe$5, "capture", capture$2());
    let _pipe$7 = extend_b(_pipe$6, "encode_uri", encode_uri$1());
    let _pipe$8 = extend_b(_pipe$7, "int_add", add$1());
    let _pipe$9 = extend_b(_pipe$8, "int_subtract", subtract$1());
    let _pipe$10 = extend_b(_pipe$9, "int_multiply", multiply$1());
    let _pipe$11 = extend_b(_pipe$10, "int_divide", divide$1());
    let _pipe$12 = extend_b(_pipe$11, "int_absolute", absolute$1());
    let _pipe$13 = extend_b(_pipe$12, "int_to_string", to_string$3());
    let _pipe$14 = extend_b(_pipe$13, "string_append", append$1());
    let _pipe$15 = extend_b(_pipe$14, "string_replace", replace$1());
    let _pipe$16 = extend_b(_pipe$15, "string_split", split$1());
    let _pipe$17 = extend_b(_pipe$16, "string_uppercase", uppercase$1());
    let _pipe$18 = extend_b(_pipe$17, "string_lowercase", lowercase$1());
    let _pipe$19 = extend_b(_pipe$18, "string_length", length$1());
    let _pipe$20 = extend_b(_pipe$19, "pop_grapheme", pop_grapheme$1());
    let _pipe$21 = extend_b(_pipe$20, "list_pop", pop$2());
    return extend_b(_pipe$21, "list_fold", fold$1());
  }

  class Variable extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  }

  class Lambda extends CustomType$1 {
    constructor(label, body) {
      super();
      this.label = label;
      this.body = body;
    }
  }

  let Apply$1 = class Apply extends CustomType$1 {
    constructor(func, argument) {
      super();
      this.func = func;
      this.argument = argument;
    }
  };

  class Let extends CustomType$1 {
    constructor(label, definition, body) {
      super();
      this.label = label;
      this.definition = definition;
      this.body = body;
    }
  }

  let Binary$2 = class Binary extends CustomType$1 {
    constructor(value) {
      super();
      this.value = value;
    }
  };

  let Integer$3 = class Integer extends CustomType$1 {
    constructor(value) {
      super();
      this.value = value;
    }
  };

  let Str$2 = class Str extends CustomType$1 {
    constructor(value) {
      super();
      this.value = value;
    }
  };

  class Tail extends CustomType$1 {}

  let Cons$1 = class Cons extends CustomType$1 {};

  let Vacant$1 = class Vacant extends CustomType$1 {
    constructor(comment) {
      super();
      this.comment = comment;
    }
  };

  class Empty extends CustomType$1 {}

  let Extend$2 = class Extend extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  let Select$1 = class Select extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  let Overwrite$1 = class Overwrite extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  let Tag$1 = class Tag extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  class Case extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  }

  let NoCases$1 = class NoCases extends CustomType$1 {};

  let Perform$1 = class Perform extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  let Handle$1 = class Handle extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  let Shallow$1 = class Shallow extends CustomType$1 {
    constructor(label) {
      super();
      this.label = label;
    }
  };

  let Builtin$2 = class Builtin extends CustomType$1 {
    constructor(identifier) {
      super();
      this.identifier = identifier;
    }
  };

  const unit$2 = new Empty();

  new Apply$1(new Tag$1("True"), unit$2);

  new Apply$1(new Tag$1("False"), unit$2);

  function bit_string_to_integers(loop$value, loop$acc) {
    while (true) {
      let value = loop$value;
      let acc = loop$acc;
      if (value.length == 0) {
        return reverse(acc);
      } else if (value.length >= 1) {
        let byte = value.byteAt(0);
        let rest = value.sliceAfter(1);
        loop$value = rest;
        loop$acc = toList([byte], acc);
      } else {
        throw makeError(
          "case_no_match",
          "eygir/expression",
          16,
          "bit_string_to_integers",
          "No case clause matched",
          { values: [value] }
        )
      }
    }
  }

  function print_bit_string(value) {
    let _pipe = bit_string_to_integers(value, toList([]));
    let _pipe$1 = map$1(_pipe, to_string$7);
    let _pipe$2 = join(_pipe$1, " ");
    let _pipe$3 = append$2(_pipe$2, ">");
    return ((_capture) => { return append$2("<", _capture); })(_pipe$3);
  }

  class Cont extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  let Done$1 = class Done extends CustomType$1 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  };

  function loop$1(loop$run) {
    while (true) {
      let run = loop$run;
      if (run instanceof Done$1) {
        let state = run[0];
        let envs = run[1];
        return [state, envs];
      } else if (run instanceof Cont) {
        let state = run[0];
        let envs = run[1];
        let k = run[2];
        loop$run = k(state, envs);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/jm/tree",
          25,
          "loop",
          "No case clause matched",
          { values: [run] }
        )
      }
    }
  }

  function primitive(exp, next) {
    if (exp instanceof Variable) {
      return (() => {
        throw makeError(
          "todo",
          "eyg/analysis/jm/tree",
          100,
          "primitive",
          "panic expression evaluated",
          {}
        )
      })()("not a literal");
    } else if (exp instanceof Apply$1) {
      return (() => {
        throw makeError(
          "todo",
          "eyg/analysis/jm/tree",
          100,
          "primitive",
          "panic expression evaluated",
          {}
        )
      })()("not a literal");
    } else if (exp instanceof Lambda) {
      return (() => {
        throw makeError(
          "todo",
          "eyg/analysis/jm/tree",
          100,
          "primitive",
          "panic expression evaluated",
          {}
        )
      })()("not a literal");
    } else if (exp instanceof Let) {
      return (() => {
        throw makeError(
          "todo",
          "eyg/analysis/jm/tree",
          100,
          "primitive",
          "panic expression evaluated",
          {}
        )
      })()("not a literal");
    } else if (exp instanceof Builtin$2) {
      return (() => {
        throw makeError(
          "todo",
          "eyg/analysis/jm/tree",
          100,
          "primitive",
          "panic expression evaluated",
          {}
        )
      })()("not a literal");
    } else if (exp instanceof Binary$2) {
      return [new Binary$3(), next];
    } else if (exp instanceof Str$2) {
      return [new String$2(), next];
    } else if (exp instanceof Integer$3) {
      return [new Integer$4(), next];
    } else if (exp instanceof Tail) {
      return tail(next);
    } else if (exp instanceof Cons$1) {
      return cons$1(next);
    } else if (exp instanceof Vacant$1) {
      return fresh(next);
    } else if (exp instanceof Empty) {
      return empty$1(next);
    } else if (exp instanceof Extend$2) {
      let label = exp.label;
      return extend$5(label, next);
    } else if (exp instanceof Overwrite$1) {
      let label = exp.label;
      return overwrite$2(label, next);
    } else if (exp instanceof Select$1) {
      let label = exp.label;
      return select$2(label, next);
    } else if (exp instanceof Tag$1) {
      let label = exp.label;
      return tag$1(label, next);
    } else if (exp instanceof Case) {
      let label = exp.label;
      return case_(label, next);
    } else if (exp instanceof NoCases$1) {
      return nocases$1(next);
    } else if (exp instanceof Perform$1) {
      let label = exp.label;
      return perform$2(label, next);
    } else if (exp instanceof Handle$1) {
      let label = exp.label;
      return handle$2(label, next);
    } else if (exp instanceof Shallow$1) {
      let label = exp.label;
      return handle$2(label, next);
    } else {
      throw makeError(
        "case_no_match",
        "eyg/analysis/jm/tree",
        95,
        "primitive",
        "No case clause matched",
        { values: [exp] }
      )
    }
  }

  function infer(exp, type_, eff) {
    return infer_env(exp, type_, eff, new$$2(), new$$2(), 0);
  }

  function infer_env(exp, type_, eff, env, sub, next) {
    let types = new$$2();
    let path = toList([]);
    let acc = [sub, next, types];
    let envs = new$$2();
    return loop$1(
      step$2(
        acc,
        env,
        envs,
        exp,
        path,
        type_,
        eff,
        (var0, var1) => { return new Done$1(var0, var1); },
      ),
    );
  }

  function step$2(
    loop$acc,
    loop$env,
    loop$envs,
    loop$exp,
    loop$rev,
    loop$type_,
    loop$eff,
    loop$k
  ) {
    while (true) {
      let acc = loop$acc;
      let env = loop$env;
      let envs = loop$envs;
      let exp = loop$exp;
      let rev = loop$rev;
      let type_ = loop$type_;
      let eff = loop$eff;
      let k = loop$k;
      if (exp instanceof Variable) {
        let x = exp.label;
        return fetch$1(acc, rev, env, x, type_, envs, k);
      } else if (exp instanceof Apply$1) {
        let e1 = exp.func;
        let e2 = exp.argument;
        let sub = acc[0];
        let next = acc[1];
        let types = acc[2];
        let types$1 = insert$1(types, rev, new Ok$1(type_));
        let $ = fresh(next);
        let arg = $[0];
        let next$1 = $[1];
        let acc$1 = [sub, next$1, types$1];
        let func = new Fun$1(arg, eff, type_);
        loop$acc = acc$1;
        loop$env = env;
        loop$envs = envs;
        loop$exp = e1;
        loop$rev = toList([0], rev);
        loop$type_ = func;
        loop$eff = eff;
        loop$k = (acc, envs) => {
          return step$2(
            acc,
            env,
            envs,
            e2,
            toList([1], rev),
            arg,
            eff,
            (acc, envs) => { return new Cont(acc, envs, k); },
          );
        };
      } else if (exp instanceof Lambda) {
        let x = exp.label;
        let e1 = exp.body;
        let sub = acc[0];
        let next = acc[1];
        let types = acc[2];
        let $ = fresh(next);
        let arg = $[0];
        let next$1 = $[1];
        let $1 = fresh(next$1);
        let eff$1 = $1[0];
        let next$2 = $1[1];
        let $2 = fresh(next$2);
        let ret = $2[0];
        let next$3 = $2[1];
        let acc$1 = [sub, next$3, types];
        let envs$1 = insert$1(envs, rev, env);
        let func = new Fun$1(arg, eff$1, ret);
        let acc$2 = unify_at(acc$1, rev, type_, func);
        let env$1 = extend$4(env, x, mono(arg));
        loop$acc = acc$2;
        loop$env = env$1;
        loop$envs = envs$1;
        loop$exp = e1;
        loop$rev = toList([0], rev);
        loop$type_ = ret;
        loop$eff = eff$1;
        loop$k = (acc, envs) => { return new Cont(acc, envs, k); };
      } else if (exp instanceof Let) {
        let x = exp.label;
        let e1 = exp.definition;
        let e2 = exp.body;
        let sub = acc[0];
        let next = acc[1];
        let types = acc[2];
        let types$1 = insert$1(types, rev, new Ok$1(type_));
        let $ = fresh(next);
        let inner = $[0];
        let next$1 = $[1];
        let acc$1 = [sub, next$1, types$1];
        loop$acc = acc$1;
        loop$env = env;
        loop$envs = envs;
        loop$exp = e1;
        loop$rev = toList([0], rev);
        loop$type_ = inner;
        loop$eff = eff;
        loop$k = (acc, envs) => {
          let env$1 = extend$4(env, x, generalise(acc[0], env, inner));
          return step$2(
            acc,
            env$1,
            envs,
            e2,
            toList([1], rev),
            type_,
            eff,
            (acc, envs) => { return new Cont(acc, envs, k); },
          );
        };
      } else if (exp instanceof Builtin$2) {
        let x = exp.identifier;
        return fetch$1(acc, rev, builtins(), x, type_, envs, k);
      } else {
        let literal = exp;
        let sub = acc[0];
        let next = acc[1];
        let types = acc[2];
        let $ = primitive(literal, next);
        let found = $[0];
        let next$1 = $[1];
        let acc$1 = [sub, next$1, types];
        return new Cont(unify_at(acc$1, rev, type_, found), envs, k);
      }
    }
  }

  function unify_at(acc, path, expected, found) {
    let sub = acc[0];
    let next = acc[1];
    let types = acc[2];
    return unify_at$1(expected, found, sub, next, types, path);
  }

  function fetch$1(acc, path, env, x, type_, envs, k) {
    let $ = get(env, x);
    if ($.isOk()) {
      let scheme = $[0];
      let sub = acc[0];
      let next = acc[1];
      let types = acc[2];
      let $1 = instantiate(scheme, next);
      let found = $1[0];
      let next$1 = $1[1];
      let acc$1 = [sub, next$1, types];
      return new Cont(unify_at(acc$1, path, type_, found), envs, k);
    } else if (!$.isOk() && !$[0]) {
      let sub = acc[0];
      let next = acc[1];
      let types = acc[2];
      let $1 = fresh(next);
      let unmatched = $1[0];
      let next$1 = $1[1];
      let types$1 = insert$1(
        types,
        path,
        new Error$1([new MissingVariable(x), type_, unmatched]),
      );
      let acc$1 = [sub, next$1, types$1];
      return new Cont(acc$1, envs, k);
    } else {
      throw makeError(
        "case_no_match",
        "eyg/analysis/jm/tree",
        135,
        "fetch",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function alert(message) {
    window.alert(message);
  }

  function encodeURI(value) {
    return globalThis.encodeURI(value);
  }

  function decodeURI(value) {
    return globalThis.decodeURI(value);
  }

  function decodeURIComponent(value) {
    return globalThis.decodeURIComponent(value);
  }

  function locationSearch() {
    const search = globalThis.location.search;
    if (search == "") {
      return new Error$1()
    } else {
      return new Ok$1(search.slice(1))
    }
  }

  function onClick(f) {
    document.onclick = function (event) {
      let arg = event.target.closest("[data-click]")?.dataset?.click;
      // can deserialize in language
      if (arg) {
        f(arg);
      }
    };
  }
  // above is a version of global handling of clicks but that in an app or area of activity
  // or should it be qwik is global
  // BUT the above function can only be called once so it need to be start of loader run setup

  function onKeyDown(f) {
    document.onkeydown = function (event) {
      // let arg = event.target.closest("[data-keydown]")?.dataset?.click;
      // can deserialize in language
      // event.key
      // if (arg) {
      f(event.key);
      // }
    };
  }

  function addEventListener(el, type, listener) {
    el.addEventListener(type, listener);
    return function () {
      el.removeEventListener(type, listener);
    };
  }

  function target(event) {
    return event.target;
  }
  function preventDefault(event) {
    return event.preventDefault();
  }

  function eventKey(event) {
    return event.key;
  }
  // -------- window/file --------

  async function showOpenFilePicker(options) {
    try {
      return new Ok$1(await window.showOpenFilePicker());
    } catch (error) {
      return new Error$1();
    }
  }

  async function showSaveFilePicker(options) {
    try {
      return new Ok$1(await window.showSaveFilePicker());
    } catch (error) {
      return new Error$1();
    }
  }

  function getFile(fileHandle) {
    return fileHandle.getFile();
  }

  function fileText(file) {
    return file.text();
  }

  // works on file handles from opening but requires more permissions.
  function createWritable(fileHandle) {
    return fileHandle.createWritable();
  }

  function write(writableStream, blob) {
    return writableStream.write(blob);
  }
  function close(writableStream) {
    return writableStream.close();
  }

  function blob(strings, arg) {
    return new Blob(strings, {
      type: arg,
    });
  }

  // -------- window/selection --------

  function getSelection() {
    const selection = window.getSelection();
    if (!selection) {
      return new Error$1();
    }
    return new Ok$1(selection);
  }

  function getRangeAt(selection, index) {
    const range = selection.getRangeAt(0);
    if (!range) {
      return new Error$1();
    }
    return new Ok$1(range);
  }

  // -------- document --------

  function querySelector(el, query) {
    let found = el.querySelector(query);
    if (!found) {
      return new Error$1();
    }
    return new Ok$1(found);
  }
  // could use array from in Gleam code but don't want to return dynamic to represent elementList
  // directly typing array of elements is cleanest
  function querySelectorAll(query) {
    return Array.from(document.querySelectorAll(query));
  }

  function doc() {
    return document;
  }

  function closest(element, query) {
    let r = element.closest(query);
    if (r) {
      return new Ok$1(r);
    }
    return new Error$1();
  }

  function nextElementSibling(el) {
    return el.nextElementSibling;
  }

  function innerText(e) {
    return e.innerText;
  }
  function setInnerHTML(e, content) {
    e.innerHTML = content;
  }

  function datasetGet(el, key) {
    if (key in el.dataset) {
      return new Ok$1(el.dataset[key]);
    }
    return new Error$1(undefined);
  }

  // https://stackoverflow.com/questions/1966476/how-can-i-process-each-letter-of-text-using-javascript
  function foldGraphmemes(string, initial, f) {
    let value = initial;
    // for (const ch of string) {
    //   value = f(value, ch);
    // }
    [...string].forEach((c, i) => {
      value = f(value, c, i);
    });
    return value;
  }

  function replace_at$1(original, from, to, new$) {
    let letters = to_graphemes(original);
    let pre = take$1(letters, from);
    let post = drop$1(letters, to);
    let _pipe = flatten(toList([pre, to_graphemes(new$), post]));
    return concat(_pipe);
  }

  class Default extends CustomType$1 {}

  class Keyword extends CustomType$1 {}

  class Missing extends CustomType$1 {}

  class Hole extends CustomType$1 {}

  let Integer$2 = class Integer extends CustomType$1 {};

  let String$1 = class String extends CustomType$1 {};

  class Label extends CustomType$1 {}

  let Effect$2 = class Effect extends CustomType$1 {};

  let Builtin$1 = class Builtin extends CustomType$1 {};

  function type_at(path, analysis) {
    if (analysis instanceof Some) {
      let analysis$1 = analysis[0];
      let types = analysis$1[2];
      let $ = get(types, reverse(path));
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/print",
          41,
          "type_at",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let t = $[0];
      return new Some(t);
    } else if (analysis instanceof None) {
      return new None();
    } else {
      throw makeError(
        "case_no_match",
        "easel/print",
        38,
        "type_at",
        "No case clause matched",
        { values: [analysis] }
      )
    }
  }

  function is_error(path, analysis) {
    let $ = type_at(path, analysis);
    if ($ instanceof Some) {
      let t = $[0];
      return is_error$1(t);
    } else if ($ instanceof None) {
      return false;
    } else {
      throw makeError(
        "case_no_match",
        "easel/print",
        49,
        "is_error",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function print_keyword(keyword, loc, acc, err) {
    if (!(loc instanceof Location)) {
      throw makeError(
        "assignment_no_match",
        "easel/print",
        417,
        "print_keyword",
        "Assignment pattern did not match",
        { value: loc }
      )
    }
    let path = loc.path;
    return foldGraphmemes(
      keyword,
      acc,
      (acc, ch) => { return toList([[ch, path, -1, new Keyword(), err]], acc); },
    );
  }

  function path_to_string(path) {
    let _pipe = map$1(path, to_string$7);
    return join(_pipe, "j");
  }

  function print_with_offset(content, loc, style, err, acc, info, _) {
    if (!(loc instanceof Location)) {
      throw makeError(
        "assignment_no_match",
        "easel/print",
        428,
        "print_with_offset",
        "Assignment pattern did not match",
        { value: loc }
      )
    }
    let path = loc.path;
    let info$1 = insert$1(info, path_to_string(loc.path), length$3(acc));
    let $ = (() => {
      if (content === "") {
        return ["_", new Missing()];
      } else {
        return [content, style];
      }
    })();
    let content$1 = $[0];
    let style$1 = $[1];
    let acc$1 = foldGraphmemes(
      content$1,
      acc,
      (acc, ch, i) => { return toList([[ch, path, i, style$1, err]], acc); },
    );
    return [acc$1, info$1];
  }

  function print_block(source, loc, br, acc, info, analysis) {
    let err = is_error(loc.path, analysis);
    if (source instanceof Let) {
      let $ = open(loc);
      if ($) {
        let br_inner = append$2(br, "  ");
        let acc$1 = print_keyword(append$2("{", br_inner), loc, acc, err);
        let $1 = do_print(source, loc, br_inner, acc$1, info, analysis);
        let acc$2 = $1[0];
        let info$1 = $1[1];
        let acc$3 = print_keyword(append$2(br, "}"), loc, acc$2, err);
        return [acc$3, info$1];
      } else if (!$) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword("{ ... }", loc, acc, err);
        return [acc$1, info$1];
      } else {
        throw makeError(
          "case_no_match",
          "easel/print",
          281,
          "print_block",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else {
      return do_print(source, loc, br, acc, info, analysis);
    }
  }

  function do_print(
    loop$source,
    loop$loc,
    loop$br,
    loop$acc,
    loop$info,
    loop$analysis
  ) {
    while (true) {
      let source = loop$source;
      let loc = loop$loc;
      let br = loop$br;
      let acc = loop$acc;
      let info = loop$info;
      let analysis = loop$analysis;
      let err = is_error(loc.path, analysis);
      if (source instanceof Lambda) {
        let param = source.label;
        let body = source.body;
        let $ = print_with_offset(
          param,
          loc,
          new Default(),
          err,
          acc,
          info);
        let acc$1 = $[0];
        let info$1 = $[1];
        let acc$2 = print_keyword(" -> ", loc, acc$1, err);
        return print_block(
          body,
          child$1(loc, 0),
          br,
          acc$2,
          info$1,
          analysis,
        );
      } else if (source instanceof Apply$1 && source.func instanceof Select$1) {
        let label = source.func.label;
        let from = source.argument;
        let $ = print_block(
          from,
          child$1(loc, 1),
          br,
          acc,
          info,
          analysis,
        );
        let acc$1 = $[0];
        let info$1 = $[1];
        let info$2 = insert$1(
          info$1,
          path_to_string(loc.path),
          length$3(acc$1),
        );
        let acc$2 = print_keyword(".", loc, acc$1, err);
        return print_with_offset(
          label,
          child$1(loc, 0),
          new Default(),
          err,
          acc$2,
          info$2);
      } else if (source instanceof Apply$1 &&
      source.func instanceof Apply$1 &&
      source.func.func instanceof Cons$1) {
        let item = source.func.argument;
        let tail = source.argument;
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword("[", loc, acc, err);
        let $ = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br,
          acc$1,
          info$1,
          analysis,
        );
        let acc$2 = $[0];
        let info$2 = $[1];
        return print_tail(
          tail,
          child$1(loc, 1),
          br,
          acc$2,
          info$2,
          analysis,
        );
      } else if (source instanceof Apply$1 &&
      source.func instanceof Apply$1 &&
      source.func.func instanceof Extend$2) {
        let label = source.func.func.label;
        let item = source.func.argument;
        let tail = source.argument;
        let acc$1 = print_keyword("{", loc, acc, err);
        let $ = print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info);
        let acc$2 = $[0];
        let info$1 = $[1];
        let acc$3 = print_keyword(": ", loc, acc$2, err);
        let $1 = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br,
          acc$3,
          info$1,
          analysis,
        );
        let acc$4 = $1[0];
        let info$2 = $1[1];
        return print_extend(
          tail,
          child$1(loc, 1),
          br,
          acc$4,
          info$2,
          analysis,
        );
      } else if (source instanceof Apply$1 &&
      source.func instanceof Apply$1 &&
      source.func.func instanceof Overwrite$1) {
        let label = source.func.func.label;
        let item = source.func.argument;
        let tail = source.argument;
        let acc$1 = print_keyword("{", loc, acc, err);
        let $ = print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info);
        let acc$2 = $[0];
        let info$1 = $[1];
        let acc$3 = print_keyword(": ", loc, acc$2, err);
        let $1 = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br,
          acc$3,
          info$1,
          analysis,
        );
        let acc$4 = $1[0];
        let info$2 = $1[1];
        return print_extend(
          tail,
          child$1(loc, 1),
          br,
          acc$4,
          info$2,
          analysis,
        );
      } else if (source instanceof Apply$1 &&
      source.func instanceof Apply$1 &&
      source.func.func instanceof Case) {
        let label = source.func.func.label;
        let item = source.func.argument;
        let tail = source.argument;
        let acc$1 = print_keyword("match {", loc, acc, err);
        let br_inner = append$2(br, "  ");
        let acc$2 = print_keyword(br_inner, loc, acc$1, err);
        let $ = print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$2,
          info);
        let acc$3 = $[0];
        let info$1 = $[1];
        let acc$4 = print_keyword(" ", loc, acc$3, err);
        let $1 = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br_inner,
          acc$4,
          info$1,
          analysis,
        );
        let acc$5 = $1[0];
        let info$2 = $1[1];
        return print_match(
          tail,
          child$1(loc, 1),
          br,
          br_inner,
          acc$5,
          info$2,
          analysis,
        );
      } else if (source instanceof Apply$1) {
        let func = source.func;
        let arg = source.argument;
        let $ = print_block(
          func,
          child$1(loc, 0),
          br,
          acc,
          info,
          analysis,
        );
        let acc$1 = $[0];
        let info$1 = $[1];
        let info$2 = insert$1(
          info$1,
          path_to_string(loc.path),
          length$3(acc$1),
        );
        let acc$2 = print_keyword("(", loc, acc$1, err);
        let $1 = print_block(
          arg,
          child$1(loc, 1),
          br,
          acc$2,
          info$2,
          analysis,
        );
        let acc$3 = $1[0];
        let info$3 = $1[1];
        let acc$4 = print_keyword(")", loc, acc$3, err);
        return [acc$4, info$3];
      } else if (source instanceof Let) {
        let label = source.label;
        let value = source.definition;
        let then$ = source.body;
        let acc$1 = print_keyword("let ", loc, acc, err);
        let $ = print_with_offset(
          label,
          loc,
          new Default(),
          err,
          acc$1,
          info);
        let acc$2 = $[0];
        let info$1 = $[1];
        let acc$3 = print_keyword(" = ", loc, acc$2, err);
        let $1 = print_block(
          value,
          child$1(loc, 0),
          br,
          acc$3,
          info$1,
          analysis,
        );
        let acc$4 = $1[0];
        let info$2 = $1[1];
        let acc$5 = print_keyword(br, loc, acc$4, err);
        loop$source = then$;
        loop$loc = child$1(loc, 1);
        loop$br = br;
        loop$acc = acc$5;
        loop$info = info$2;
        loop$analysis = analysis;
      } else if (source instanceof Variable) {
        let label = source.label;
        return print_with_offset(
          label,
          loc,
          new Default(),
          err,
          acc,
          info);
      } else if (source instanceof Vacant$1) {
        let content = (() => {
          if (analysis instanceof Some) {
            let sub = analysis[0][0];
            let types = analysis[0][2];
            let $ = get(types, reverse(loc.path));
            if (!$.isOk() && !$[0]) {
              return "todo";
            } else if ($.isOk()) {
              let inferred = $[0];
              if (inferred.isOk()) {
                let t = inferred[0];
                let t$1 = resolve(t, sub);
                return render_type(t$1);
              } else if (!inferred.isOk()) {
                let r = inferred[0][0];
                inferred[0][1];
                inferred[0][2];
                return render_failure(r);
              } else {
                throw makeError(
                  "case_no_match",
                  "easel/print",
                  169,
                  "do_print",
                  "No case clause matched",
                  { values: [inferred] }
                )
              }
            } else {
              throw makeError(
                "case_no_match",
                "easel/print",
                166,
                "do_print",
                "No case clause matched",
                { values: [$] }
              )
            }
          } else if (analysis instanceof None) {
            return "todo";
          } else {
            throw makeError(
              "case_no_match",
              "easel/print",
              164,
              "do_print",
              "No case clause matched",
              { values: [analysis] }
            )
          }
        })();
        return print_with_offset(
          content,
          loc,
          new Hole(),
          err,
          acc,
          info);
      } else if (source instanceof Binary$2) {
        let value = source.value;
        return print_with_offset(
          print_bit_string(value),
          loc,
          new Integer$2(),
          err,
          acc,
          info);
      } else if (source instanceof Integer$3) {
        let value = source.value;
        return print_with_offset(
          to_string$7(value),
          loc,
          new Integer$2(),
          err,
          acc,
          info);
      } else if (source instanceof Str$2) {
        let value = source.value;
        let acc$1 = toList([["\"", loc.path, -1, new String$1(), err]], acc);
        return print_with_offset(
          append$2(value, "\""),
          loc,
          new String$1(),
          err,
          acc$1,
          info);
      } else if (source instanceof Tail) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc) + 1,
        );
        let acc$1 = print_keyword("[]", loc, acc, err);
        return [acc$1, info$1];
      } else if (source instanceof Cons$1) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword("cons", loc, acc, err);
        return [acc$1, info$1];
      } else if (source instanceof Empty) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc) + 1,
        );
        let acc$1 = print_keyword("{}", loc, acc, err);
        return [acc$1, info$1];
      } else if (source instanceof Extend$2) {
        let label = source.label;
        let acc$1 = toList([["+", loc.path, -1, new Label(), err]], acc);
        return print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info);
      } else if (source instanceof Select$1) {
        let label = source.label;
        let acc$1 = toList([[".", loc.path, -1, new Label(), err]], acc);
        return print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info);
      } else if (source instanceof Overwrite$1) {
        let label = source.label;
        let acc$1 = toList([["=", loc.path, -1, new Label(), err]], acc);
        return print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info);
      } else if (source instanceof Tag$1) {
        let label = source.label;
        return print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc,
          info);
      } else if (source instanceof Case) {
        let label = source.label;
        let acc$1 = toList([["|", loc.path, -1, new Label(), err]], acc);
        return print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info);
      } else if (source instanceof NoCases$1) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword("----", loc, acc, err);
        return [acc$1, info$1];
      } else if (source instanceof Perform$1) {
        let label = source.label;
        let acc$1 = print_keyword("perform ", loc, acc, err);
        return print_with_offset(
          label,
          loc,
          new Effect$2(),
          err,
          acc$1,
          info);
      } else if (source instanceof Handle$1) {
        let label = source.label;
        let acc$1 = print_keyword("handle ", loc, acc, err);
        return print_with_offset(
          label,
          loc,
          new Effect$2(),
          err,
          acc$1,
          info);
      } else if (source instanceof Shallow$1) {
        let label = source.label;
        let acc$1 = print_keyword("shallow ", loc, acc, err);
        return print_with_offset(
          label,
          loc,
          new Effect$2(),
          err,
          acc$1,
          info);
      } else if (source instanceof Builtin$2) {
        let value = source.identifier;
        return print_with_offset(
          value,
          loc,
          new Builtin$1(),
          err,
          acc,
          info);
      } else {
        throw makeError(
          "case_no_match",
          "easel/print",
          57,
          "do_print",
          "No case clause matched",
          { values: [source] }
        )
      }
    }
  }

  function print(source, selection, always, analysis) {
    let loc = new Location(toList([]), selection, always);
    let $ = do_print(source, loc, "\n", toList([]), new$$2(), analysis);
    let acc = $[0];
    let info = $[1];
    return [reverse(acc), info];
  }

  function print_tail(
    loop$exp,
    loop$loc,
    loop$br,
    loop$acc,
    loop$info,
    loop$analysis
  ) {
    while (true) {
      let exp = loop$exp;
      let loc = loop$loc;
      let br = loop$br;
      let acc = loop$acc;
      let info = loop$info;
      let analysis = loop$analysis;
      let err = is_error(loc.path, analysis);
      if (exp instanceof Tail) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword("]", loc, acc, err);
        return [acc$1, info$1];
      } else if (exp instanceof Apply$1 &&
      exp.func instanceof Apply$1 &&
      exp.func.func instanceof Cons$1) {
        let item = exp.func.argument;
        let tail = exp.argument;
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword(", ", loc, acc, err);
        let $ = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br,
          acc$1,
          info$1,
          analysis,
        );
        let acc$2 = $[0];
        let info$2 = $[1];
        loop$exp = tail;
        loop$loc = child$1(loc, 1);
        loop$br = br;
        loop$acc = acc$2;
        loop$info = info$2;
        loop$analysis = analysis;
      } else {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword(", ..", loc, acc, err);
        let $ = print_block(exp, loc, br, acc$1, info$1, analysis);
        let acc$2 = $[0];
        let info$2 = $[1];
        let acc$3 = print_keyword("]", loc, acc$2, err);
        return [acc$3, info$2];
      }
    }
  }

  function print_extend(
    loop$exp,
    loop$loc,
    loop$br,
    loop$acc,
    loop$info,
    loop$analysis
  ) {
    while (true) {
      let exp = loop$exp;
      let loc = loop$loc;
      let br = loop$br;
      let acc = loop$acc;
      let info = loop$info;
      let analysis = loop$analysis;
      let err = is_error(loc.path, analysis);
      if (exp instanceof Empty) {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword("}", loc, acc, err);
        return [acc$1, info$1];
      } else if (exp instanceof Apply$1 &&
      exp.func instanceof Apply$1 &&
      exp.func.func instanceof Extend$2) {
        let label = exp.func.func.label;
        let item = exp.func.argument;
        let tail = exp.argument;
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword(", ", loc, acc, err);
        let $ = print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info$1);
        let acc$2 = $[0];
        let info$2 = $[1];
        let acc$3 = print_keyword(": ", loc, acc$2, err);
        let $1 = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br,
          acc$3,
          info$2,
          analysis,
        );
        let acc$4 = $1[0];
        let info$3 = $1[1];
        loop$exp = tail;
        loop$loc = child$1(loc, 1);
        loop$br = br;
        loop$acc = acc$4;
        loop$info = info$3;
        loop$analysis = analysis;
      } else if (exp instanceof Apply$1 &&
      exp.func instanceof Apply$1 &&
      exp.func.func instanceof Overwrite$1) {
        let label = exp.func.func.label;
        let item = exp.func.argument;
        let tail = exp.argument;
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword(", ", loc, acc, err);
        let $ = print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info$1);
        let acc$2 = $[0];
        let info$2 = $[1];
        let acc$3 = print_keyword(": ", loc, acc$2, err);
        let $1 = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br,
          acc$3,
          info$2,
          analysis,
        );
        let acc$4 = $1[0];
        let info$3 = $1[1];
        loop$exp = tail;
        loop$loc = child$1(loc, 1);
        loop$br = br;
        loop$acc = acc$4;
        loop$info = info$3;
        loop$analysis = analysis;
      } else {
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc),
        );
        let acc$1 = print_keyword(", ..", loc, acc, err);
        let $ = print_block(exp, loc, br, acc$1, info$1, analysis);
        let acc$2 = $[0];
        let info$2 = $[1];
        let acc$3 = print_keyword("}", loc, acc$2, err);
        return [acc$3, info$2];
      }
    }
  }

  function print_match(
    loop$exp,
    loop$loc,
    loop$br,
    loop$br_inner,
    loop$acc,
    loop$info,
    loop$analysis
  ) {
    while (true) {
      let exp = loop$exp;
      let loc = loop$loc;
      let br = loop$br;
      let br_inner = loop$br_inner;
      let acc = loop$acc;
      let info = loop$info;
      let analysis = loop$analysis;
      let err = is_error(loc.path, analysis);
      if (exp instanceof NoCases$1) {
        let acc$1 = print_keyword(br, loc, acc, err);
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc$1),
        );
        let acc$2 = print_keyword("}", loc, acc$1, err);
        return [acc$2, info$1];
      } else if (exp instanceof Apply$1 &&
      exp.func instanceof Apply$1 &&
      exp.func.func instanceof Case) {
        let label = exp.func.func.label;
        let item = exp.func.argument;
        let tail = exp.argument;
        let acc$1 = print_keyword(br_inner, loc, acc, err);
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc$1),
        );
        let $ = print_with_offset(
          label,
          loc,
          new Label(),
          err,
          acc$1,
          info$1);
        let acc$2 = $[0];
        let info$2 = $[1];
        let acc$3 = print_keyword(" ", loc, acc$2, err);
        let $1 = print_block(
          item,
          child$1(child$1(loc, 0), 1),
          br_inner,
          acc$3,
          info$2,
          analysis,
        );
        let acc$4 = $1[0];
        let info$3 = $1[1];
        loop$exp = tail;
        loop$loc = child$1(loc, 1);
        loop$br = br;
        loop$br_inner = br_inner;
        loop$acc = acc$4;
        loop$info = info$3;
        loop$analysis = analysis;
      } else {
        let acc$1 = print_keyword(br_inner, loc, acc, err);
        let info$1 = insert$1(
          info,
          path_to_string(loc.path),
          length$3(acc$1),
        );
        let $ = print_block(exp, loc, br_inner, acc$1, info$1, analysis);
        let acc$2 = $[0];
        let info$2 = $[1];
        let acc$3 = print_keyword(br, loc, acc$2, err);
        let acc$4 = print_keyword("}", loc, acc$3, err);
        return [acc$4, info$2];
      }
    }
  }

  function child(expression, index) {
    if (expression instanceof Lambda && index === 0) {
      let param = expression.label;
      let body = expression.body;
      return new Ok$1(
        [body, (_capture) => { return new Lambda(param, _capture); }],
      );
    } else if (expression instanceof Apply$1 && index === 0) {
      let func = expression.func;
      let arg = expression.argument;
      return new Ok$1([func, (_capture) => { return new Apply$1(_capture, arg); }]);
    } else if (expression instanceof Apply$1 && index === 1) {
      let func = expression.func;
      let arg = expression.argument;
      return new Ok$1([arg, (_capture) => { return new Apply$1(func, _capture); }]);
    } else if (expression instanceof Let && index === 0) {
      let label = expression.label;
      let value = expression.definition;
      let then$ = expression.body;
      return new Ok$1(
        [value, (_capture) => { return new Let(label, _capture, then$); }],
      );
    } else if (expression instanceof Let && index === 1) {
      let label = expression.label;
      let value = expression.definition;
      let then$ = expression.body;
      return new Ok$1(
        [then$, (_capture) => { return new Let(label, value, _capture); }],
      );
    } else {
      return new Error$1(undefined);
    }
  }

  function do_zipper(expression, path, acc) {
    if (path.hasLength(0)) {
      return new Ok$1(
        [
          expression,
          (new$) => {
            return fold$4(
              acc,
              new$,
              (element, build) => { return build(element); },
            );
          },
        ],
      );
    } else if (path.atLeastLength(1)) {
      let index = path.head;
      let path$1 = path.tail;
      return then$(
        child(expression, index),
        (_use0) => {
          let child$1 = _use0[0];
          let rebuild = _use0[1];
          return do_zipper(child$1, path$1, toList([rebuild], acc));
        },
      );
    } else {
      throw makeError(
        "case_no_match",
        "easel/zipper",
        13,
        "do_zipper",
        "No case clause matched",
        { values: [path] }
      )
    }
  }

  function at(expression, path) {
    return do_zipper(expression, path, toList([]));
  }

  // element and node are the same thing when talking about an HTML element
  // Text node is not an element
  // the closest function exists only on elements
  function elementIndex(node) {
    const startElement =
      node.nodeType == Node.TEXT_NODE ? node.parentElement : node;
    let count = 0;
    let e = startElement.previousElementSibling;
    while (e) {
      count += e.textContent.length;
      e = e.previousElementSibling;
    }
    return count;
  }

  function startIndex(range) {
    return elementIndex(range.startContainer) + range.startOffset;
  }

  function endIndex(range) {
    return elementIndex(range.endContainer) + range.endOffset;
  }

  function handleInput$1(event, insert_text, insert_paragraph) {
    // Always at least one range
    // If not zero range collapse to cursor
    const range = event.getTargetRanges()[0];
    const start = startIndex(range);
    const end = endIndex(range);
    if (event.inputType == "insertText") {
      return insert_text(event.data, start, end);
    }
    if (event.inputType == "insertParagraph") {
      return insert_paragraph(start);
    }
    if (
      event.inputType == "deleteContentBackward" ||
      event.inputType == "deleteContentForward"
    ) {
      return insert_text("", start, end);
    }
    if (event.inputType == "insertFromPaste") {
      return insert_text(event.dataTransfer.getData("text"), start, end);
    }
    console.log(event);
  }

  function placeCursor(pre, offset) {
    let e = pre.children[0];
    let countdown = offset;
    while (countdown > e.textContent.length) {
      countdown -= e.textContent.length;
      e = e.nextElementSibling;
    }
    const range = document.createRange();
    const selection = window.getSelection();
    selection.removeAllRanges();

    // range needs to be set on the text node
    range.setStart(e.firstChild, countdown);
    range.setEnd(e.firstChild, countdown);
    selection.addRange(range);
  }

  function setTimeout(callback, delay) {
    globalThis.setTimeout(callback, delay);
  }

  function log(value) {
    console.log(value);
  }

  class NotAFunction extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class UndefinedVariable extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Vacant extends CustomType$1 {
    constructor(comment) {
      super();
      this.comment = comment;
    }
  }

  class NoMatch extends CustomType$1 {
    constructor(term) {
      super();
      this.term = term;
    }
  }

  class UnhandledEffect extends CustomType$1 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  class IncorrectTerm extends CustomType$1 {
    constructor(expected, got) {
      super();
      this.expected = expected;
      this.got = got;
    }
  }

  class MissingField extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  let Binary$1 = class Binary extends CustomType$1 {
    constructor(value) {
      super();
      this.value = value;
    }
  };

  let Integer$1 = class Integer extends CustomType$1 {
    constructor(value) {
      super();
      this.value = value;
    }
  };

  let Str$1 = class Str extends CustomType$1 {
    constructor(value) {
      super();
      this.value = value;
    }
  };

  let LinkedList$1 = class LinkedList extends CustomType$1 {
    constructor(elements) {
      super();
      this.elements = elements;
    }
  };

  let Record$1 = class Record extends CustomType$1 {
    constructor(fields) {
      super();
      this.fields = fields;
    }
  };

  class Tagged extends CustomType$1 {
    constructor(label, value) {
      super();
      this.label = label;
      this.value = value;
    }
  }

  let Function$1 = class Function extends CustomType$1 {
    constructor(param, body, env, path) {
      super();
      this.param = param;
      this.body = body;
      this.env = env;
      this.path = path;
    }
  };

  class Defunc extends CustomType$1 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  let Promise$1 = class Promise extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  };

  class Cons extends CustomType$1 {}

  let Extend$1 = class Extend extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  };

  class Overwrite extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Select extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Tag extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Match extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class NoCases extends CustomType$1 {}

  class Perform extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Handle extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Resume extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  class Shallow extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Builtin extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Arg extends CustomType$1 {
    constructor(x0, x1, x2, x3) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
      this[3] = x3;
    }
  }

  class Apply extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  class Assign extends CustomType$1 {
    constructor(x0, x1, x2, x3) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
      this[3] = x3;
    }
  }

  class CallWith extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  class Delimit extends CustomType$1 {
    constructor(x0, x1, x2, x3, x4) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
      this[3] = x3;
      this[4] = x4;
    }
  }

  class Kont extends CustomType$1 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  class Value extends CustomType$1 {
    constructor(term) {
      super();
      this.term = term;
    }
  }

  let Effect$1 = class Effect extends CustomType$1 {
    constructor(label, lifted, rev, env, continuation) {
      super();
      this.label = label;
      this.lifted = lifted;
      this.rev = rev;
      this.env = env;
      this.continuation = continuation;
    }
  };

  class Abort extends CustomType$1 {
    constructor(reason, rev, env, k) {
      super();
      this.reason = reason;
      this.rev = rev;
      this.env = env;
      this.k = k;
    }
  }

  class Async extends CustomType$1 {
    constructor(promise, rev, env, k) {
      super();
      this.promise = promise;
      this.rev = rev;
      this.env = env;
      this.k = k;
    }
  }

  class Arity1 extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Arity2 extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Arity3 extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class E extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class V extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class K extends CustomType$1 {
    constructor(x0, x1, x2, x3) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
      this[3] = x3;
    }
  }

  class Done extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Env extends CustomType$1 {
    constructor(scope, builtins) {
      super();
      this.scope = scope;
      this.builtins = builtins;
    }
  }

  const unit$1 = new Record$1(toList([]));

  const true$ = new Tagged("True", unit$1);

  const false$ = new Tagged("False", unit$1);

  function ok(value) {
    return new Tagged("Ok", value);
  }

  function error(reason) {
    return new Tagged("Error", reason);
  }

  function field$1(term, field) {
    if (term instanceof Record$1) {
      let fields = term.fields;
      let $ = key_find(fields, field);
      if ($.isOk()) {
        let value = $[0];
        return new Ok$1(value);
      } else if (!$.isOk() && !$[0]) {
        return new Error$1(undefined);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          227,
          "field",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else {
      return new Error$1(undefined);
    }
  }

  function prim(return$, rev, env, k) {
    return [new V(return$), rev, env, k];
  }

  function call_builtin(key, applied, rev, env, kont) {
    let $ = get(env.builtins, key);
    if ($.isOk()) {
      let func = $[0];
      if (func instanceof Arity1 && applied.hasLength(1)) {
        let impl = func[0];
        let x = applied.head;
        return impl(x, rev, env, kont);
      } else if (func instanceof Arity2 && applied.hasLength(2)) {
        let impl = func[0];
        let x = applied.head;
        let y = applied.tail.head;
        return impl(x, y, rev, env, kont);
      } else if (func instanceof Arity3 && applied.hasLength(3)) {
        let impl = func[0];
        let x = applied.head;
        let y = applied.tail.head;
        let z = applied.tail.tail.head;
        return impl(x, y, z, rev, env, kont);
      } else {
        return [
          new V(new Value(new Defunc(new Builtin(key), applied))),
          rev,
          env,
          kont,
        ];
      }
    } else if (!$.isOk() && !$[0]) {
      return prim(
        new Abort(new UndefinedVariable(key), rev, env, kont),
        rev,
        env,
        kont,
      );
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/interpreter",
        319,
        "call_builtin",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function cons(item, tail, rev, env, k) {
    if (tail instanceof LinkedList$1) {
      let elements = tail.elements;
      return new Value(new LinkedList$1(toList([item], elements)));
    } else {
      let term = tail;
      return new Abort(new IncorrectTerm("LinkedList", term), rev, env, k);
    }
  }

  function select$1(label, arg, rev, env, k) {
    if (arg instanceof Record$1) {
      let fields = arg.fields;
      let $ = key_find(fields, label);
      if ($.isOk()) {
        let value = $[0];
        return new Value(value);
      } else if (!$.isOk() && !$[0]) {
        return new Abort(new MissingField(label), rev, env, k);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          466,
          "select",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else {
      let term = arg;
      return new Abort(
        new IncorrectTerm(append$2("Record (-select) ", label), term),
        rev,
        env,
        k,
      );
    }
  }

  function extend$3(label, value, rest, rev, env, k) {
    if (rest instanceof Record$1) {
      let fields = rest.fields;
      return new Value(new Record$1(toList([[label, value]], fields)));
    } else {
      let term = rest;
      return new Abort(new IncorrectTerm("Record (-extend) ", term), rev, env, k);
    }
  }

  function overwrite$1(label, value, rest, rev, env, k) {
    if (rest instanceof Record$1) {
      let fields = rest.fields;
      let $ = key_pop(fields, label);
      if ($.isOk()) {
        let fields$1 = $[0][1];
        return new Value(new Record$1(toList([[label, value]], fields$1)));
      } else if (!$.isOk() && !$[0]) {
        return new Abort(new MissingField(label), rev, env, k);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          490,
          "overwrite",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else {
      let term = rest;
      return new Abort(
        new IncorrectTerm("Record (-overwrite) ", term),
        rev,
        env,
        k,
      );
    }
  }

  function do_pop$1(loop$k, loop$label, loop$popped) {
    while (true) {
      let k = loop$k;
      let label = loop$label;
      let popped = loop$popped;
      if (k instanceof Some) {
        let k$1 = k[0];
        if (k$1 instanceof Kont &&
        k$1[0] instanceof Delimit &&
        k$1[0][0] === label) {
          k$1[0][0];
          let h = k$1[0][1];
          let rev = k$1[0][2];
          let e = k$1[0][3];
          let shallow$1 = k$1[0][4];
          let rest = k$1[1];
          return new Ok$1([popped, h, rev, e, rest, shallow$1]);
        } else if (k$1 instanceof Kont) {
          let kontinue = k$1[0];
          let rest = k$1[1];
          loop$k = rest;
          loop$label = label;
          loop$popped = new Some(new Kont(kontinue, popped));
        } else {
          throw makeError(
            "case_no_match",
            "eyg/runtime/interpreter",
            515,
            "do_pop",
            "No case clause matched",
            { values: [k$1] }
          )
        }
      } else if (k instanceof None) {
        return new Error$1(undefined);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          513,
          "do_pop",
          "No case clause matched",
          { values: [k] }
        )
      }
    }
  }

  function pop$1(k, label) {
    return do_pop$1(k, label, new None());
  }

  function move(loop$delimited, loop$acc) {
    while (true) {
      let delimited = loop$delimited;
      let acc = loop$acc;
      if (delimited instanceof None) {
        return acc;
      } else if (delimited instanceof Some && delimited[0] instanceof Kont) {
        let step$1 = delimited[0][0];
        let rest = delimited[0][1];
        loop$delimited = rest;
        loop$acc = new Some(new Kont(step$1, acc));
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          530,
          "move",
          "No case clause matched",
          { values: [delimited] }
        )
      }
    }
  }

  function perform$1(label, arg, i_rev, i_env, k) {
    let $ = pop$1(k, label);
    if ($.isOk()) {
      let popped = $[0][0];
      let h = $[0][1];
      let rev = $[0][2];
      let e = $[0][3];
      let k$1 = $[0][4];
      let shallow$1 = $[0][5];
      let resume = (() => {
        if (shallow$1) {
          return new Defunc(new Resume(popped, i_rev, i_env), toList([]));
        } else if (!shallow$1) {
          let popped$1 = new Some(
            new Kont(new Delimit(label, h, rev, e, false), popped),
          );
          return new Defunc(new Resume(popped$1, i_rev, i_env), toList([]));
        } else {
          throw makeError(
            "case_no_match",
            "eyg/runtime/interpreter",
            539,
            "perform",
            "No case clause matched",
            { values: [shallow$1] }
          )
        }
      })();
      let k$2 = new Some(
        new Kont(
          new CallWith(arg, rev, e),
          new Some(new Kont(new CallWith(resume, rev, e), k$1)),
        ),
      );
      return [new V(new Value(h)), rev, e, k$2];
    } else if (!$.isOk() && !$[0]) {
      return [
        new V(new Effect$1(label, arg, i_rev, i_env, k)),
        i_rev,
        i_env,
        new None(),
      ];
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/interpreter",
        537,
        "perform",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function field_to_string(field) {
    let k = field[0];
    let v = field[1];
    return concat(toList([k, ": ", to_string$2(v)]));
  }

  function to_string$2(term) {
    if (term instanceof Binary$1) {
      let value = term.value;
      return print_bit_string(value);
    } else if (term instanceof Integer$1) {
      let value = term.value;
      return to_string$7(value);
    } else if (term instanceof Str$1) {
      let value = term.value;
      return concat(toList(["\"", value, "\""]));
    } else if (term instanceof LinkedList$1) {
      let items = term.elements;
      let _pipe = map$1(items, to_string$2);
      let _pipe$1 = intersperse(_pipe, ", ");
      let _pipe$2 = prepend(_pipe$1, "[");
      let _pipe$3 = append$3(_pipe$2, toList(["]"]));
      return concat(_pipe$3);
    } else if (term instanceof Record$1) {
      let fields = term.fields;
      let _pipe = fields;
      let _pipe$1 = map$1(_pipe, field_to_string);
      let _pipe$2 = intersperse(_pipe$1, ", ");
      let _pipe$3 = prepend(_pipe$2, "{");
      let _pipe$4 = append$3(_pipe$3, toList(["}"]));
      return concat(_pipe$4);
    } else if (term instanceof Tagged) {
      let label = term.label;
      let value = term.value;
      return concat(toList([label, "(", to_string$2(value), ")"]));
    } else if (term instanceof Function$1) {
      let param = term.param;
      return concat(toList(["(", param, ") -> { ... }"]));
    } else if (term instanceof Defunc) {
      let d = term[0];
      let args = term[1];
      return concat(
        toList(
          ["Defunc: ", inspect$5(d), " "],
          intersperse(map$1(args, to_string$2), ", "),
        ),
      );
    } else if (term instanceof Promise$1) {
      return concat(toList(["Promise: "]));
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/interpreter",
        167,
        "to_string",
        "No case clause matched",
        { values: [term] }
      )
    }
  }

  function reason_to_string$1(reason) {
    if (reason instanceof UndefinedVariable) {
      let var$ = reason[0];
      return append$2("variable undefined: ", var$);
    } else if (reason instanceof IncorrectTerm) {
      let expected = reason.expected;
      let got = reason.got;
      return concat(
        toList(["unexpected term, expected: ", expected, " got: ", to_string$2(got)]),
      );
    } else if (reason instanceof MissingField) {
      let field$1 = reason[0];
      return concat(toList(["missing record field: ", field$1]));
    } else if (reason instanceof NoMatch) {
      let term = reason.term;
      return concat(toList(["no cases matched for: ", to_string$2(term)]));
    } else if (reason instanceof NotAFunction) {
      let term = reason[0];
      return concat(toList(["function expected got: ", to_string$2(term)]));
    } else if (reason instanceof UnhandledEffect && reason[0] === "Abort") {
      let reason$1 = reason[1];
      return concat(
        toList(["Aborted with reason: ", to_string$2(reason$1)]),
      );
    } else if (reason instanceof UnhandledEffect) {
      let effect = reason[0];
      let lift = reason[1];
      return concat(
        toList(["unhandled effect ", effect, "(", to_string$2(lift), ")"]),
      );
    } else if (reason instanceof Vacant) {
      let note = reason.comment;
      return concat(toList(["tried to run a todo: ", note]));
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/interpreter",
        203,
        "reason_to_string",
        "No case clause matched",
        { values: [reason] }
      )
    }
  }

  function match$1(label, matched, otherwise, value, rev, env, k) {
    if (value instanceof Tagged) {
      let l = value.label;
      let term = value.value;
      let $ = l === label;
      if ($) {
        return step_call(matched, term, rev, env, k);
      } else if (!$) {
        return step_call(otherwise, value, rev, env, k);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          501,
          "match",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else {
      let term = value;
      let message = concat(toList(["Tagged |", label]));
      return prim(
        new Abort(new IncorrectTerm(message, term), rev, env, k),
        rev,
        env,
        k,
      );
    }
  }

  function step_call(f, arg, rev, env, k) {
    if (f instanceof Function$1) {
      let param = f.param;
      let body = f.body;
      let captured = f.env;
      let rev$1 = f.path;
      let env$1 = env.withFields({ scope: toList([[param, arg]], captured) });
      return [new E(body), rev$1, env$1, k];
    } else if (f instanceof Defunc) {
      let switch$ = f[0];
      let applied = f[1];
      if (switch$ instanceof Cons && applied.hasLength(1)) {
        let item = applied.head;
        return prim(cons(item, arg, rev, env, k), rev, env, k);
      } else if (switch$ instanceof Extend$1 && applied.hasLength(1)) {
        let label = switch$[0];
        let value = applied.head;
        return prim(extend$3(label, value, arg, rev, env, k), rev, env, k);
      } else if (switch$ instanceof Overwrite && applied.hasLength(1)) {
        let label = switch$[0];
        let value = applied.head;
        return prim(overwrite$1(label, value, arg, rev, env, k), rev, env, k);
      } else if (switch$ instanceof Select && applied.hasLength(0)) {
        let label = switch$[0];
        return prim(select$1(label, arg, rev, env, k), rev, env, k);
      } else if (switch$ instanceof Tag && applied.hasLength(0)) {
        let label = switch$[0];
        return prim(new Value(new Tagged(label, arg)), rev, env, k);
      } else if (switch$ instanceof Match && applied.hasLength(2)) {
        let label = switch$[0];
        let branch = applied.head;
        let rest = applied.tail.head;
        return match$1(label, branch, rest, arg, rev, env, k);
      } else if (switch$ instanceof NoCases && applied.hasLength(0)) {
        return prim(new Abort(new NoMatch(arg), rev, env, k), rev, env, k);
      } else if (switch$ instanceof Perform && applied.hasLength(0)) {
        let label = switch$[0];
        return perform$1(label, arg, rev, env, k);
      } else if (switch$ instanceof Handle && applied.hasLength(1)) {
        let label = switch$[0];
        let handler = applied.head;
        return deep(label, handler, arg, rev, env, k);
      } else if (switch$ instanceof Resume && applied.hasLength(0)) {
        let popped = switch$[0];
        let rev$1 = switch$[1];
        let env$1 = switch$[2];
        let k$1 = move(popped, k);
        return [new V(new Value(arg)), rev$1, env$1, k$1];
      } else if (switch$ instanceof Shallow && applied.hasLength(1)) {
        let label = switch$[0];
        let handler = applied.head;
        return shallow$1(label, handler, arg, rev, env, k);
      } else if (switch$ instanceof Builtin) {
        let key = switch$[0];
        let applied$1 = applied;
        return call_builtin(
          key,
          append$3(applied$1, toList([arg])),
          rev,
          env,
          k,
        );
      } else {
        let switch$1 = switch$;
        let applied$1 = append$3(applied, toList([arg]));
        return [new V(new Value(new Defunc(switch$1, applied$1))), rev, env, k];
      }
    } else {
      let term = f;
      return prim(new Abort(new NotAFunction(term), rev, env, k), rev, env, k);
    }
  }

  function apply_k(loop$value, loop$k) {
    while (true) {
      let value = loop$value;
      let k = loop$k;
      if (k instanceof Some && k[0] instanceof Kont) {
        let switch$ = k[0][0];
        let k$1 = k[0][1];
        if (switch$ instanceof Assign) {
          let label = switch$[0];
          let then$ = switch$[1];
          let rev = switch$[2];
          let env = switch$[3];
          let env$1 = env.withFields({ scope: toList([[label, value]], env.scope) });
          return new K(new E(then$), rev, env$1, k$1);
        } else if (switch$ instanceof Arg) {
          let arg = switch$[0];
          let rev = switch$[1];
          let call_rev = switch$[2];
          let env = switch$[3];
          return new K(
            new E(arg),
            rev,
            env,
            new Some(new Kont(new Apply(value, call_rev, env), k$1)),
          );
        } else if (switch$ instanceof Apply) {
          let f = switch$[0];
          let rev = switch$[1];
          let env = switch$[2];
          let $ = step_call(f, value, rev, env, k$1);
          let c = $[0];
          let rev$1 = $[1];
          let e = $[2];
          let k$2 = $[3];
          return new K(c, rev$1, e, k$2);
        } else if (switch$ instanceof CallWith) {
          let arg = switch$[0];
          let rev = switch$[1];
          let env = switch$[2];
          let $ = step_call(value, arg, rev, env, k$1);
          let c = $[0];
          let rev$1 = $[1];
          let e = $[2];
          let k$2 = $[3];
          return new K(c, rev$1, e, k$2);
        } else if (switch$ instanceof Delimit) {
          loop$value = value;
          loop$k = k$1;
        } else {
          throw makeError(
            "case_no_match",
            "eyg/runtime/interpreter",
            433,
            "apply_k",
            "No case clause matched",
            { values: [switch$] }
          )
        }
      } else if (k instanceof None) {
        return new Done(new Value(value));
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          431,
          "apply_k",
          "No case clause matched",
          { values: [k] }
        )
      }
    }
  }

  function step$1(exp, rev, env, k) {
    if (exp instanceof E && exp[0] instanceof Lambda) {
      let param = exp[0].label;
      let body = exp[0].body;
      return new K(
        new V(new Value(new Function$1(param, body, env.scope, rev))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Apply$1) {
      let f = exp[0].func;
      let arg = exp[0].argument;
      return new K(
        new E(f),
        toList([0], rev),
        env,
        new Some(new Kont(new Arg(arg, toList([1], rev), rev, env), k)),
      );
    } else if (exp instanceof E && exp[0] instanceof Variable) {
      let x = exp[0].label;
      let return$ = (() => {
        let $ = key_find(env.scope, x);
        if ($.isOk()) {
          let term = $[0];
          return new Value(term);
        } else if (!$.isOk() && !$[0]) {
          return new Abort(new UndefinedVariable(x), rev, env, k);
        } else {
          throw makeError(
            "case_no_match",
            "eyg/runtime/interpreter",
            389,
            "step",
            "No case clause matched",
            { values: [$] }
          )
        }
      })();
      return new K(new V(return$), rev, env, k);
    } else if (exp instanceof E && exp[0] instanceof Let) {
      let var$ = exp[0].label;
      let value = exp[0].definition;
      let then$ = exp[0].body;
      return new K(
        new E(value),
        toList([0], rev),
        env,
        new Some(new Kont(new Assign(var$, then$, toList([1], rev), env), k)),
      );
    } else if (exp instanceof E && exp[0] instanceof Binary$2) {
      let value = exp[0].value;
      return new K(new V(new Value(new Binary$1(value))), rev, env, k);
    } else if (exp instanceof E && exp[0] instanceof Integer$3) {
      let value = exp[0].value;
      return new K(new V(new Value(new Integer$1(value))), rev, env, k);
    } else if (exp instanceof E && exp[0] instanceof Str$2) {
      let value = exp[0].value;
      return new K(new V(new Value(new Str$1(value))), rev, env, k);
    } else if (exp instanceof E && exp[0] instanceof Tail) {
      return new K(new V(new Value(new LinkedList$1(toList([])))), rev, env, k);
    } else if (exp instanceof E && exp[0] instanceof Cons$1) {
      return new K(
        new V(new Value(new Defunc(new Cons(), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Vacant$1) {
      let comment = exp[0].comment;
      return new K(
        new V(new Abort(new Vacant(comment), rev, env, k)),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Select$1) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Select(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Tag$1) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Tag(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Perform$1) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Perform(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Empty) {
      return new K(new V(new Value(new Record$1(toList([])))), rev, env, k);
    } else if (exp instanceof E && exp[0] instanceof Extend$2) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Extend$1(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Overwrite$1) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Overwrite(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Case) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Match(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof NoCases$1) {
      return new K(
        new V(new Value(new Defunc(new NoCases(), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Handle$1) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Handle(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Shallow$1) {
      let label = exp[0].label;
      return new K(
        new V(new Value(new Defunc(new Shallow(label), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof E && exp[0] instanceof Builtin$2) {
      let identifier = exp[0].identifier;
      return new K(
        new V(new Value(new Defunc(new Builtin(identifier), toList([])))),
        rev,
        env,
        k,
      );
    } else if (exp instanceof V && exp[0] instanceof Value) {
      let value = exp[0].term;
      return apply_k(value, k);
    } else if (exp instanceof V) {
      let other = exp[0];
      return new Done(other);
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/interpreter",
        381,
        "step",
        "No case clause matched",
        { values: [exp] }
      )
    }
  }

  function loop(loop$c, loop$p, loop$e, loop$k) {
    while (true) {
      let c = loop$c;
      let p = loop$p;
      let e = loop$e;
      let k = loop$k;
      let next = step$1(c, p, e, k);
      if (next instanceof K) {
        let c$1 = next[0];
        let p$1 = next[1];
        let e$1 = next[2];
        let k$1 = next[3];
        loop$c = c$1;
        loop$p = p$1;
        loop$e = e$1;
        loop$k = k$1;
      } else if (next instanceof Done) {
        let return$ = next[0];
        return return$;
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          356,
          "loop",
          "No case clause matched",
          { values: [next] }
        )
      }
    }
  }

  function handle$1(loop$return, loop$extrinsic) {
    while (true) {
      let return$ = loop$return;
      let extrinsic = loop$extrinsic;
      if (return$ instanceof Effect$1) {
        let label = return$.label;
        let term = return$.lifted;
        let rev = return$.rev;
        let env = return$.env;
        let k = return$.continuation;
        let $ = get(extrinsic, label);
        if ($.isOk()) {
          let handler = $[0];
          let $1 = handler(term, k);
          let c = $1[0];
          let rev$1 = $1[1];
          let e = $1[2];
          let k$1 = $1[3];
          let return$1 = loop(c, rev$1, e, k$1);
          loop$return = return$1;
          loop$extrinsic = extrinsic;
        } else if (!$.isOk() && !$[0]) {
          return new Abort(new UnhandledEffect(label, term), rev, env, k);
        } else {
          throw makeError(
            "case_no_match",
            "eyg/runtime/interpreter",
            87,
            "handle",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else if (return$ instanceof Value) {
        let term = return$.term;
        return new Value(term);
      } else if (return$ instanceof Abort) {
        let failure = return$.reason;
        let rev = return$.rev;
        let env = return$.env;
        let k = return$.k;
        return new Abort(failure, rev, env, k);
      } else if (return$ instanceof Async) {
        let promise = return$.promise;
        let rev = return$.rev;
        let env = return$.env;
        let k = return$.k;
        return new Async(promise, rev, env, k);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          83,
          "handle",
          "No case clause matched",
          { values: [return$] }
        )
      }
    }
  }

  function flatten_promise(ret, extrinsic) {
    if (ret instanceof Value) {
      let term = ret.term;
      return resolve$1(new Ok$1(term));
    } else if (ret instanceof Abort) {
      let failure = ret.reason;
      let path = ret.rev;
      let env = ret.env;
      return resolve$1(new Error$1([failure, path, env]));
    } else if (ret instanceof Effect$1) {
      let label = ret.label;
      let lifted = ret.lifted;
      let rev = ret.rev;
      let env = ret.env;
      return resolve$1(
        new Error$1([new UnhandledEffect(label, lifted), rev, env]),
      );
    } else if (ret instanceof Async) {
      let p = ret.promise;
      let rev = ret.rev;
      let env = ret.env;
      let k = ret.k;
      return then(
        p,
        (return$) => {
          let next = loop(new V(new Value(return$)), rev, env, k);
          return flatten_promise(handle$1(next, extrinsic), extrinsic);
        },
      );
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/interpreter",
        62,
        "flatten_promise",
        "No case clause matched",
        { values: [ret] }
      )
    }
  }

  function eval_call(f, arg, env, k) {
    let $ = step_call(f, arg, toList([]), env, k);
    let c = $[0];
    let rev = $[1];
    let e = $[2];
    let k$1 = $[3];
    return loop(c, rev, e, k$1);
  }

  function eval$$1(exp, env, k) {
    return loop(new E(exp), toList([]), env, k);
  }

  function loop_till(loop$c, loop$p, loop$e, loop$k) {
    while (true) {
      let c = loop$c;
      let p = loop$p;
      let e = loop$e;
      let k = loop$k;
      let $ = step$1(c, p, e, k);
      if ($ instanceof K) {
        let c$1 = $[0];
        let p$1 = $[1];
        let e$1 = $[2];
        let k$1 = $[3];
        loop$c = c$1;
        loop$p = p$1;
        loop$e = e$1;
        loop$k = k$1;
      } else if ($ instanceof Done) {
        let return$ = $[0];
        let $1 = isEqual(new V(return$), c);
        if (!$1) {
          throw makeError(
            "assignment_no_match",
            "eyg/runtime/interpreter",
            366,
            "loop_till",
            "Assignment pattern did not match",
            { value: $1 }
          )
        }
        return [return$, e];
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/interpreter",
          363,
          "loop_till",
          "No case clause matched",
          { values: [$] }
        )
      }
    }
  }

  function resumable(exp, env, k) {
    return loop_till(new E(exp), toList([]), env, k);
  }

  function deep(label, handle, exec, rev, env, k) {
    let k$1 = new Some(new Kont(new Delimit(label, handle, rev, env, false), k));
    return step_call(exec, new Record$1(toList([])), rev, env, k$1);
  }

  function shallow$1(label, handle, exec, rev, env, k) {
    let k$1 = new Some(new Kont(new Delimit(label, handle, rev, env, true), k));
    return step_call(exec, new Record$1(toList([])), rev, env, k$1);
  }

  class CustomType {
    inspect() {
      let field = (label) => {
        let value = inspect(this[label]);
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

  class Result extends CustomType {
    static isResult(data) {
      let variant = data?.__gleam_prelude_variant__;
      return variant === "Ok" || variant === "Error";
    }
  }

  class Ok extends Result {
    constructor(value) {
      super();
      this[0] = value;
    }

    get __gleam_prelude_variant__() {
      return "Ok";
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

    get __gleam_prelude_variant__() {
      return "Error";
    }

    isOk() {
      return false;
    }
  }

  function inspect(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect).join(", ")}))`;
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
      return inspectObject(v);
    }
  }

  function inspectObject(v) {
    let [keys, get] = getters(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect(k)}: ${inspect(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function getters(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  function json_to_string(json) {
    return JSON.stringify(json);
  }

  function object$1(entries) {
    return Object.fromEntries(entries);
  }

  function identity(x) {
    return x;
  }

  function decode$1(string) {
    try {
      const result = JSON.parse(string);
      return new Ok(result);
    } catch (err) {
      return new Error(getJsonDecodeError(err, string));
    }
  }

  function getJsonDecodeError(stdErr, json) {
    if (isUnexpectedEndOfInput(stdErr)) return new UnexpectedEndOfInput();
    return toUnexpectedByteError(stdErr, json);
  }

  /**
   * Matches unexpected end of input messages in:
   * - Chromium (edge, chrome, node)
   * - Spidermonkey (firefox)
   * - JavascriptCore (safari)
   *
   * Note that Spidermonkey and JavascriptCore will both incorrectly report some
   * UnexpectedByte errors as UnexpectedEndOfInput errors. For example:
   *
   * @example
   * // in JavascriptCore
   * JSON.parse('{"a"]: "b"})
   * // => JSON Parse error: Expected ':' before value
   *
   * JSON.parse('{"a"')
   * // => JSON Parse error: Expected ':' before value
   *
   * // in Chromium (correct)
   * JSON.parse('{"a"]: "b"})
   * // => Unexpected token ] in JSON at position 4
   *
   * JSON.parse('{"a"')
   * // => Unexpected end of JSON input
   */
  function isUnexpectedEndOfInput(err) {
    const unexpectedEndOfInputRegex =
      /((unexpected (end|eof))|(end of data)|(unterminated string)|(json( parse error|\.parse)\: expected '(\:|\}|\])'))/i;
    return unexpectedEndOfInputRegex.test(err.message);
  }

  /**
   * Converts a SyntaxError to an UnexpectedByte error based on the JS runtime.
   *
   * For Chromium, the unexpected byte and position are reported by the runtime.
   *
   * For JavascriptCore, only the unexpected byte is reported by the runtime, so
   * there is no way to know which position that character is in unless we then
   * parse the string again ourselves. So instead, the position is reported as 0.
   *
   * For Spidermonkey, the position is reported by the runtime as a line and column number
   * and the unexpected byte is found using those coordinates.
   *
   * @param {'chromium' | 'spidermonkey' | 'jscore'} runtime
   * @param {SyntaxError} err
   * @param {string} json
   * @returns {UnexpectedByte}
   */
  function toUnexpectedByteError(err, json) {
    let converters = [
      v8UnexpectedByteError,
      oldV8UnexpectedByteError,
      jsCoreUnexpectedByteError,
      spidermonkeyUnexpectedByteError,
    ];

    for (let converter of converters) {
      let result = converter(err, json);
      if (result) return result;
    }

    return new UnexpectedByte("", 0);
  }

  /**
   * Matches unexpected byte messages in:
   * - V8 (edge, chrome, node)
   *
   * Matches the character but not the position as this is no longer reported by
   * V8. Boo!
   */
  function v8UnexpectedByteError(err) {
    const regex = /unexpected token '(.)', ".+" is not valid JSON/i;
    const match = regex.exec(err.message);
    if (!match) return null;
    const byte = toHex(match[1]);
    return new UnexpectedByte(byte, -1);
  }

  /**
   * Matches unexpected byte messages in:
   * - V8 (edge, chrome, node)
   *
   * No longer works in current versions of V8.
   *
   * Matches the character and its position.
   */
  function oldV8UnexpectedByteError(err) {
    const regex = /unexpected token (.) in JSON at position (\d+)/i;
    const match = regex.exec(err.message);
    if (!match) return null;
    const byte = toHex(match[1]);
    const position = Number(match[2]);
    return new UnexpectedByte(byte, position);
  }

  /**
   * Matches unexpected byte messages in:
   * - Spidermonkey (firefox)
   *
   * Matches the position in a 2d grid only and not the character.
   */
  function spidermonkeyUnexpectedByteError(err, json) {
    const regex =
      /(unexpected character|expected .*) at line (\d+) column (\d+)/i;
    const match = regex.exec(err.message);
    if (!match) return null;
    const line = Number(match[2]);
    const column = Number(match[3]);
    const position = getPositionFromMultiline(line, column, json);
    const byte = toHex(json[position]);
    return new UnexpectedByte(byte, position);
  }

  /**
   * Matches unexpected byte messages in:
   * - JavascriptCore (safari)
   *
   * JavascriptCore only reports what the character is and not its position.
   */
  function jsCoreUnexpectedByteError(err) {
    const regex = /unexpected (identifier|token) "(.)"/i;
    const match = regex.exec(err.message);
    if (!match) return null;
    const byte = toHex(match[2]);
    return new UnexpectedByte(byte, 0);
  }

  function toHex(char) {
    return "0x" + char.charCodeAt(0).toString(16).toUpperCase();
  }

  /**
   * Gets the position of a character in a flattened (i.e. single line) string
   * from a line and column number. Note that the position is 0-indexed and
   * the line and column numbers are 1-indexed.
   *
   * @param {number} line
   * @param {number} column
   * @param {string} string
   */
  function getPositionFromMultiline(line, column, string) {
    if (line === 1) return column - 1;

    let currentLn = 1;
    let position = 0;
    string.split("").find((char, idx) => {
      if (char === "\n") currentLn += 1;
      if (currentLn === line) {
        position = idx + column;
        return true;
      }
      return false;
    });

    return position;
  }

  class UnexpectedEndOfInput extends CustomType {}

  class UnexpectedByte extends CustomType {
    constructor(byte, position) {
      super();
      this.byte = byte;
      this.position = position;
    }
  }

  class UnexpectedFormat extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function do_decode(json, decoder) {
    return then$(
      decode$1(json),
      (dynamic_value) => {
        let _pipe = decoder(dynamic_value);
        return map_error(
          _pipe,
          (var0) => { return new UnexpectedFormat(var0); },
        );
      },
    );
  }

  function decode(json, decoder) {
    return do_decode(json, decoder);
  }

  function to_string$1(json) {
    return json_to_string(json);
  }

  function string$2(input) {
    return identity(input);
  }

  function int(input) {
    return identity(input);
  }

  function object(entries) {
    return object$1(entries);
  }

  function encode64(input, padding) {
    let encoded = encode64$1(input);
    if (padding) {
      return encoded;
    } else if (!padding) {
      return replace$2(encoded, "=", "");
    } else {
      throw makeError$3(
        "case_no_match",
        "gleam/base",
        8,
        "encode64",
        "No case clause matched",
        { values: [padding] }
      )
    }
  }

  function decode64(encoded) {
    let padded = (() => {
      let $ = remainderInt(
        byte_size(from_string(encoded)),
        4
      );
      if ($ === 0) {
        return encoded;
      } else {
        let n = $;
        return append$2(encoded, repeat("=", 4 - n));
      }
    })();
    return decode64$1(padded);
  }

  function label$1() {
    return any$1(toList([field$2("label", string$3), field$2("l", string$3)]));
  }

  function base_encoded(value) {
    return then$(
      string$3(value),
      (encoded) => {
        return map_error(
          decode64(encoded),
          (_) => {
            return toList([
              new DecodeError("base64 encoded", encoded, toList([""])),
            ]);
          },
        );
      },
    );
  }

  function decoder(x) {
    return then$(
      any$1(toList([field$2("node", string$3), field$2("0", string$3)]))(x),
      (node) => {
        return (() => {
          if (node === "v") {
            return decode1((var0) => { return new Variable(var0); }, label$1());
          } else if (node === "variable") {
            return decode1((var0) => { return new Variable(var0); }, label$1());
          } else if (node === "f") {
            return decode2(
              (var0, var1) => { return new Lambda(var0, var1); },
              label$1(),
              any$1(toList([field$2("body", decoder), field$2("b", decoder)])),
            );
          } else if (node === "function") {
            return decode2(
              (var0, var1) => { return new Lambda(var0, var1); },
              label$1(),
              any$1(toList([field$2("body", decoder), field$2("b", decoder)])),
            );
          } else if (node === "a") {
            return decode2(
              (var0, var1) => { return new Apply$1(var0, var1); },
              any$1(toList([field$2("function", decoder), field$2("f", decoder)])),
              any$1(toList([field$2("arg", decoder), field$2("a", decoder)])),
            );
          } else if (node === "call") {
            return decode2(
              (var0, var1) => { return new Apply$1(var0, var1); },
              any$1(toList([field$2("function", decoder), field$2("f", decoder)])),
              any$1(toList([field$2("arg", decoder), field$2("a", decoder)])),
            );
          } else if (node === "l") {
            return decode3(
              (var0, var1, var2) => { return new Let(var0, var1, var2); },
              label$1(),
              any$1(toList([field$2("value", decoder), field$2("v", decoder)])),
              any$1(toList([field$2("then", decoder), field$2("t", decoder)])),
            );
          } else if (node === "let") {
            return decode3(
              (var0, var1, var2) => { return new Let(var0, var1, var2); },
              label$1(),
              any$1(toList([field$2("value", decoder), field$2("v", decoder)])),
              any$1(toList([field$2("then", decoder), field$2("t", decoder)])),
            );
          } else if (node === "x") {
            return decode1(
              (var0) => { return new Binary$2(var0); },
              any$1(
                toList([field$2("value", base_encoded), field$2("v", base_encoded)]),
              ),
            );
          } else if (node === "i") {
            return decode1(
              (var0) => { return new Integer$3(var0); },
              any$1(toList([field$2("value", int$1), field$2("v", int$1)])),
            );
          } else if (node === "integer") {
            return decode1(
              (var0) => { return new Integer$3(var0); },
              any$1(toList([field$2("value", int$1), field$2("v", int$1)])),
            );
          } else if (node === "s") {
            return decode1(
              (var0) => { return new Str$2(var0); },
              any$1(toList([field$2("value", string$3), field$2("v", string$3)])),
            );
          } else if (node === "binary") {
            return decode1(
              (var0) => { return new Str$2(var0); },
              any$1(toList([field$2("value", string$3), field$2("v", string$3)])),
            );
          } else if (node === "ta") {
            return (_) => { return new Ok$1(new Tail()); };
          } else if (node === "tail") {
            return (_) => { return new Ok$1(new Tail()); };
          } else if (node === "c") {
            return (_) => { return new Ok$1(new Cons$1()); };
          } else if (node === "cons") {
            return (_) => { return new Ok$1(new Cons$1()); };
          } else if (node === "z") {
            return decode1(
              (var0) => { return new Vacant$1(var0); },
              any$1(
                toList([
                  field$2("c", string$3),
                  (_) => { return new Ok$1("no comment"); },
                ]),
              ),
            );
          } else if (node === "vacant") {
            return decode1(
              (var0) => { return new Vacant$1(var0); },
              any$1(
                toList([
                  field$2("c", string$3),
                  (_) => { return new Ok$1("no comment"); },
                ]),
              ),
            );
          } else if (node === "u") {
            return (_) => { return new Ok$1(new Empty()); };
          } else if (node === "empty") {
            return (_) => { return new Ok$1(new Empty()); };
          } else if (node === "e") {
            return decode1((var0) => { return new Extend$2(var0); }, label$1());
          } else if (node === "extend") {
            return decode1((var0) => { return new Extend$2(var0); }, label$1());
          } else if (node === "g") {
            return decode1((var0) => { return new Select$1(var0); }, label$1());
          } else if (node === "select") {
            return decode1((var0) => { return new Select$1(var0); }, label$1());
          } else if (node === "o") {
            return decode1((var0) => { return new Overwrite$1(var0); }, label$1());
          } else if (node === "overwrite") {
            return decode1((var0) => { return new Overwrite$1(var0); }, label$1());
          } else if (node === "t") {
            return decode1((var0) => { return new Tag$1(var0); }, label$1());
          } else if (node === "tag") {
            return decode1((var0) => { return new Tag$1(var0); }, label$1());
          } else if (node === "m") {
            return decode1((var0) => { return new Case(var0); }, label$1());
          } else if (node === "case") {
            return decode1((var0) => { return new Case(var0); }, label$1());
          } else if (node === "n") {
            return (_) => { return new Ok$1(new NoCases$1()); };
          } else if (node === "nocases") {
            return (_) => { return new Ok$1(new NoCases$1()); };
          } else if (node === "p") {
            return decode1((var0) => { return new Perform$1(var0); }, label$1());
          } else if (node === "perform") {
            return decode1((var0) => { return new Perform$1(var0); }, label$1());
          } else if (node === "h") {
            return decode1((var0) => { return new Handle$1(var0); }, label$1());
          } else if (node === "handle") {
            return decode1((var0) => { return new Handle$1(var0); }, label$1());
          } else if (node === "hs") {
            return decode1((var0) => { return new Shallow$1(var0); }, label$1());
          } else if (node === "shallow") {
            return decode1((var0) => { return new Shallow$1(var0); }, label$1());
          } else if (node === "b") {
            return decode1((var0) => { return new Builtin$2(var0); }, label$1());
          } else if (node === "builtin") {
            return decode1((var0) => { return new Builtin$2(var0); }, label$1());
          } else {
            let incorrect = node;
            return (_) => {
              return new Error$1(
                toList([new DecodeError("node", incorrect, toList(["0"]))]),
              );
            };
          }
        })()(x);
      },
    );
  }

  function from_json(raw) {
    return decode(raw, decoder);
  }

  function node(name, attributes) {
    return object(toList([["0", string$2(name)]], attributes));
  }

  function label(value) {
    return ["l", string$2(value)];
  }

  function bytes(b) {
    return string$2(encode64(b, true));
  }

  function encode(exp) {
    if (exp instanceof Variable) {
      let x = exp.label;
      return node("v", toList([label(x)]));
    } else if (exp instanceof Lambda) {
      let x = exp.label;
      let body = exp.body;
      return node("f", toList([label(x), ["b", encode(body)]]));
    } else if (exp instanceof Apply$1) {
      let func = exp.func;
      let arg = exp.argument;
      return node("a", toList([["f", encode(func)], ["a", encode(arg)]]));
    } else if (exp instanceof Let) {
      let x = exp.label;
      let value = exp.definition;
      let then$ = exp.body;
      let _pipe = toList([label(x), ["v", encode(value)], ["t", encode(then$)]]);
      return ((_capture) => { return node("l", _capture); })(_pipe);
    } else if (exp instanceof Binary$2) {
      let b = exp.value;
      return node("x", toList([["v", bytes(b)]]));
    } else if (exp instanceof Integer$3) {
      let i = exp.value;
      return node("i", toList([["v", int(i)]]));
    } else if (exp instanceof Str$2) {
      let s = exp.value;
      return node("s", toList([["v", string$2(s)]]));
    } else if (exp instanceof Tail) {
      return node("ta", toList([]));
    } else if (exp instanceof Cons$1) {
      return node("c", toList([]));
    } else if (exp instanceof Vacant$1) {
      let comment = exp.comment;
      return node("z", toList([["c", string$2(comment)]]));
    } else if (exp instanceof Empty) {
      return node("u", toList([]));
    } else if (exp instanceof Extend$2) {
      let x = exp.label;
      return node("e", toList([label(x)]));
    } else if (exp instanceof Select$1) {
      let x = exp.label;
      return node("g", toList([label(x)]));
    } else if (exp instanceof Overwrite$1) {
      let x = exp.label;
      return node("o", toList([label(x)]));
    } else if (exp instanceof Tag$1) {
      let x = exp.label;
      return node("t", toList([label(x)]));
    } else if (exp instanceof Case) {
      let x = exp.label;
      return node("m", toList([label(x)]));
    } else if (exp instanceof NoCases$1) {
      return node("n", toList([]));
    } else if (exp instanceof Perform$1) {
      let x = exp.label;
      return node("p", toList([label(x)]));
    } else if (exp instanceof Handle$1) {
      let x = exp.label;
      return node("h", toList([label(x)]));
    } else if (exp instanceof Shallow$1) {
      let x = exp.label;
      return node("hs", toList([label(x)]));
    } else if (exp instanceof Builtin$2) {
      let x = exp.identifier;
      return node("b", toList([label(x)]));
    } else {
      throw makeError(
        "case_no_match",
        "eygir/encode",
        18,
        "encode",
        "No case clause matched",
        { values: [exp] }
      )
    }
  }

  function to_json(exp) {
    return to_string$1(encode(exp));
  }

  class Closed extends CustomType$1 {}

  class Open extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Extend extends CustomType$1 {
    constructor(label, value, tail) {
      super();
      this.label = label;
      this.value = value;
      this.tail = tail;
    }
  }

  class Unbound extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Binary extends CustomType$1 {}

  class Integer extends CustomType$1 {}

  class Str extends CustomType$1 {}

  class LinkedList extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Fun extends CustomType$1 {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  class Union extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Record extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Term extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Row extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Effect extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  const unit = new Record(new Closed());

  const boolean = new Union(
    new Extend("True", unit, new Extend("False", unit, new Closed())),
  );

  function result(value, reason) {
    return new Union(
      new Extend("Ok", value, new Extend("Error", reason, new Closed())),
    );
  }

  function ftv_row(row) {
    if (row instanceof Closed) {
      return new$();
    } else if (row instanceof Open) {
      let x = row[0];
      return singleton(new Row(x));
    } else if (row instanceof Extend) {
      let value = row.value;
      let tail$1 = row.tail;
      return union(ftv(value), ftv_row(tail$1));
    } else {
      throw makeError(
        "case_no_match",
        "eyg/analysis/typ",
        44,
        "ftv_row",
        "No case clause matched",
        { values: [row] }
      )
    }
  }

  function ftv(loop$typ) {
    while (true) {
      let typ = loop$typ;
      if (typ instanceof Unbound) {
        let x = typ[0];
        return singleton(new Term(x));
      } else if (typ instanceof Binary) {
        return new$();
      } else if (typ instanceof Integer) {
        return new$();
      } else if (typ instanceof Str) {
        return new$();
      } else if (typ instanceof LinkedList) {
        let element = typ[0];
        loop$typ = element;
      } else if (typ instanceof Record) {
        let row = typ[0];
        return ftv_row(row);
      } else if (typ instanceof Union) {
        let row = typ[0];
        return ftv_row(row);
      } else if (typ instanceof Fun) {
        let from = typ[0];
        let effects = typ[1];
        let to = typ[2];
        return union(union(ftv(from), ftv_effect(effects)), ftv(to));
      } else {
        throw makeError(
          "case_no_match",
          "eyg/analysis/typ",
          32,
          "ftv",
          "No case clause matched",
          { values: [typ] }
        )
      }
    }
  }

  function ftv_effect(row) {
    if (row instanceof Closed) {
      return new$();
    } else if (row instanceof Open) {
      let x = row[0];
      return singleton(new Effect(x));
    } else if (row instanceof Extend) {
      let from = row.value[0];
      let to = row.value[1];
      let tail$1 = row.tail;
      return union(union(ftv(from), ftv(to)), ftv_effect(tail$1));
    } else {
      throw makeError(
        "case_no_match",
        "eyg/analysis/typ",
        52,
        "ftv_effect",
        "No case clause matched",
        { values: [row] }
      )
    }
  }

  function any(term) {
    return new Ok$1(term);
  }

  function integer(term) {
    if (term instanceof Integer$1) {
      let value = term.value;
      return new Ok$1(value);
    } else {
      return new Error$1(new IncorrectTerm("Integer", term));
    }
  }

  function string$1(term) {
    if (term instanceof Str$1) {
      let value = term.value;
      return new Ok$1(value);
    } else {
      return new Error$1(new IncorrectTerm("String", term));
    }
  }

  function list(term) {
    if (term instanceof LinkedList$1) {
      let elements = term.elements;
      return new Ok$1(elements);
    } else {
      return new Error$1(new IncorrectTerm("List", term));
    }
  }

  function field(key, inner, term) {
    if (term instanceof Record$1) {
      let fields = term.fields;
      let $ = key_find(fields, key);
      if ($.isOk()) {
        let value = $[0];
        return inner(value);
      } else if (!$.isOk() && !$[0]) {
        return new Error$1(new MissingField(key));
      } else {
        throw makeError(
          "case_no_match",
          "harness/ffi/cast",
          34,
          "field",
          "No case clause matched",
          { values: [$] }
        )
      }
    } else {
      return new Error$1(new IncorrectTerm("Record", term));
    }
  }

  function promise(term) {
    if (term instanceof Promise$1) {
      let js_promise = term[0];
      return new Ok$1(js_promise);
    } else {
      return new Error$1(new IncorrectTerm("Promise", term));
    }
  }

  function require(result, rev, env, k, then$) {
    if (result.isOk()) {
      let value = result[0];
      return then$(value);
    } else if (!result.isOk()) {
      let reason = result[0];
      return prim(new Abort(reason, rev, env, k), rev, env, k);
    } else {
      throw makeError(
        "case_no_match",
        "harness/ffi/cast",
        50,
        "require",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function do_vars_used(loop$exp, loop$env, loop$found) {
    while (true) {
      let exp = loop$exp;
      let env = loop$env;
      let found = loop$found;
      if (exp instanceof Variable) {
        let v = exp.label;
        let $ = !contains$1(env, v) && !contains$1(found, v);
        if ($) {
          return toList([v], found);
        } else if (!$) {
          return found;
        } else {
          throw makeError(
            "case_no_match",
            "eyg/runtime/capture",
            168,
            "do_vars_used",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else if (exp instanceof Lambda) {
        let param = exp.label;
        let body = exp.body;
        loop$exp = body;
        loop$env = toList([param], env);
        loop$found = found;
      } else if (exp instanceof Apply$1) {
        let func = exp.func;
        let arg = exp.argument;
        let found$1 = do_vars_used(func, env, found);
        loop$exp = arg;
        loop$env = env;
        loop$found = found$1;
      } else if (exp instanceof Let) {
        let label = exp.label;
        let value = exp.definition;
        let then$ = exp.body;
        let found$1 = do_vars_used(value, env, found);
        loop$exp = then$;
        loop$env = toList([label], env);
        loop$found = found$1;
      } else {
        return found;
      }
    }
  }

  function vars_used(exp, env) {
    return reverse(do_vars_used(exp, env, toList([])));
  }

  function capture_defunc(switch$, args, env) {
    let exp = (() => {
      if (switch$ instanceof Cons) {
        return new Cons$1();
      } else if (switch$ instanceof Extend$1) {
        let label = switch$[0];
        return new Extend$2(label);
      } else if (switch$ instanceof Overwrite) {
        let label = switch$[0];
        return new Overwrite$1(label);
      } else if (switch$ instanceof Select) {
        let label = switch$[0];
        return new Select$1(label);
      } else if (switch$ instanceof Tag) {
        let label = switch$[0];
        return new Tag$1(label);
      } else if (switch$ instanceof Match) {
        let label = switch$[0];
        return new Case(label);
      } else if (switch$ instanceof NoCases) {
        return new NoCases$1();
      } else if (switch$ instanceof Perform) {
        let label = switch$[0];
        return new Perform$1(label);
      } else if (switch$ instanceof Handle) {
        let label = switch$[0];
        return new Handle$1(label);
      } else if (switch$ instanceof Resume) {
        return (() => {
          throw makeError(
            "todo",
            "eyg/runtime/capture",
            142,
            "capture_defunc",
            "panic expression evaluated",
            {}
          )
        })()("not idea how to capture the func here, is it even possible");
      } else if (switch$ instanceof Shallow) {
        let label = switch$[0];
        return new Shallow$1(label);
      } else if (switch$ instanceof Builtin) {
        let identifier = switch$[0];
        return new Builtin$2(identifier);
      } else {
        throw makeError(
          "case_no_match",
          "eyg/runtime/capture",
          131,
          "capture_defunc",
          "No case clause matched",
          { values: [switch$] }
        )
      }
    })();
    return fold$4(
      args,
      [exp, env],
      (state, arg) => {
        let exp$1 = state[0];
        let env$1 = state[1];
        let $ = do_capture$1(arg, env$1);
        let arg$1 = $[0];
        let env$2 = $[1];
        let exp$2 = new Apply$1(exp$1, arg$1);
        return [exp$2, env$2];
      },
    );
  }

  function do_capture$1(term, env) {
    if (term instanceof Binary$1) {
      let value = term.value;
      return [new Binary$2(value), env];
    } else if (term instanceof Integer$1) {
      let value = term.value;
      return [new Integer$3(value), env];
    } else if (term instanceof Str$1) {
      let value = term.value;
      return [new Str$2(value), env];
    } else if (term instanceof LinkedList$1) {
      let items = term.elements;
      return fold_right(
        items,
        [new Tail(), env],
        (state, item) => {
          let tail = state[0];
          let env$1 = state[1];
          let $ = do_capture$1(item, env$1);
          let item$1 = $[0];
          let env$2 = $[1];
          let exp = new Apply$1(new Apply$1(new Cons$1(), item$1), tail);
          return [exp, env$2];
        },
      );
    } else if (term instanceof Record$1) {
      let fields = term.fields;
      return fold_right(
        fields,
        [new Empty(), env],
        (state, pair) => {
          let label = pair[0];
          let item = pair[1];
          let record = state[0];
          let env$1 = state[1];
          let $ = do_capture$1(item, env$1);
          let item$1 = $[0];
          let env$2 = $[1];
          let exp = new Apply$1(
            new Apply$1(new Extend$2(label), item$1),
            record,
          );
          return [exp, env$2];
        },
      );
    } else if (term instanceof Tagged) {
      let label = term.label;
      let value = term.value;
      let $ = do_capture$1(value, env);
      let value$1 = $[0];
      let env$1 = $[1];
      let exp = new Apply$1(new Tag$1(label), value$1);
      return [exp, env$1];
    } else if (term instanceof Function$1) {
      let arg = term.param;
      let body = term.body;
      let captured = term.env;
      let captured$1 = filter_map(
        vars_used(body, toList([arg])),
        (var$) => {
          return then$(
            key_find(captured, var$),
            (term) => { return new Ok$1([var$, term]); },
          );
        },
      );
      let $ = fold$4(
        captured$1,
        [env, toList([])],
        (state, new$) => {
          let env$1 = state[0];
          let wrapped = state[1];
          let var$ = new$[0];
          let term$1 = new$[1];
          let $1 = (() => {
            return do_capture$1(term$1, env$1);
          })();
          let exp = $1[0];
          let env$2 = $1[1];
          let $2 = key_find(env$2, var$);
          if ($2.isOk() && isEqual($2[0], exp)) {
            $2[0];
            return [env$2, wrapped];
          } else if ($2.isOk()) {
            let pre = filter(
              env$2,
              (e) => {
                return starts_with$1(e[0], append$2(var$, "#")) && (isEqual(
                  e[1],
                  exp
                ));
              },
            );
            if (pre.hasLength(0)) {
              let scoped_var = concat(
                toList([var$, "#", to_string$7(length$3(env$2))]),
              );
              let $3 = key_find(env$2, scoped_var);
              if ($3.isOk() || $3[0]) {
                throw makeError(
                  "assignment_no_match",
                  "eyg/runtime/capture",
                  98,
                  "",
                  "Assignment pattern did not match",
                  { value: $3 }
                )
              }
              let wrapped$1 = toList([[scoped_var, var$]], wrapped);
              let env$3 = toList([[scoped_var, exp]], env$2);
              return [env$3, wrapped$1];
            } else if (pre.hasLength(1)) {
              let scoped_var = pre.head[0];
              return [env$2, toList([[scoped_var, var$]], wrapped)];
            } else {
              throw makeError(
                "case_no_match",
                "eyg/runtime/capture",
                94,
                "",
                "No case clause matched",
                { values: [pre] }
              )
            }
          } else if (!$2.isOk() && !$2[0]) {
            return [toList([[var$, exp]], env$2), wrapped];
          } else {
            throw makeError(
              "case_no_match",
              "eyg/runtime/capture",
              83,
              "",
              "No case clause matched",
              { values: [$2] }
            )
          }
        },
      );
      let env$1 = $[0];
      let wrapped = $[1];
      let exp = new Lambda(arg, body);
      let exp$1 = fold$4(
        wrapped,
        exp,
        (exp, pair) => {
          let scoped_var = pair[0];
          let var$ = pair[1];
          return new Let(var$, new Variable(scoped_var), exp);
        },
      );
      return [exp$1, env$1];
    } else if (term instanceof Defunc) {
      let switch$ = term[0];
      let applied = term[1];
      return capture_defunc(switch$, applied, env);
    } else if (term instanceof Promise$1) {
      return (() => {
        throw makeError(
          "todo",
          "eyg/runtime/capture",
          126,
          "do_capture",
          "panic expression evaluated",
          {}
        )
      })()("not capturing promise, yet. Can be done making serialize async");
    } else {
      throw makeError(
        "case_no_match",
        "eyg/runtime/capture",
        23,
        "do_capture",
        "No case clause matched",
        { values: [term] }
      )
    }
  }

  function capture$1(term) {
    let $ = do_capture$1(term, toList([]));
    let exp = $[0];
    let env = $[1];
    return fold$4(
      env,
      exp,
      (then$, definition) => {
        let var$ = definition[0];
        let value = definition[1];
        return new Let(var$, value, then$);
      },
    );
  }

  class Scheme extends CustomType$1 {
    constructor(forall, type_) {
      super();
      this.forall = forall;
      this.type_ = type_;
    }
  }

  function init$2() {
    return [new$$2(), new$$2()];
  }

  function extend$2(state, name, parts) {
    let types = state[0];
    let implementations = state[1];
    let type_ = parts[0];
    let implementation = parts[1];
    let scheme = new Scheme(to_list(ftv(type_)), type_);
    let types$1 = insert$1(types, name, scheme);
    let values = insert$1(implementations, name, implementation);
    return [types$1, values];
  }

  function do_add(left, right, rev, env, k) {
    return require(
      integer(left),
      rev,
      env,
      k,
      (left) => {
        return require(
          integer(right),
          rev,
          env,
          k,
          (right) => {
            return prim(
              new Value(new Integer$1(left + right)),
              rev,
              env,
              k,
            );
          },
        );
      },
    );
  }

  function add() {
    let type_ = new Fun(
      new Integer(),
      new Open(0),
      new Fun(new Integer(), new Open(1), new Integer()),
    );
    return [type_, new Arity2(do_add)];
  }

  function do_subtract(left, right, rev, env, k) {
    return require(
      integer(left),
      rev,
      env,
      k,
      (left) => {
        return require(
          integer(right),
          rev,
          env,
          k,
          (right) => {
            return prim(
              new Value(new Integer$1(left - right)),
              rev,
              env,
              k,
            );
          },
        );
      },
    );
  }

  function subtract() {
    let type_ = new Fun(
      new Integer(),
      new Open(0),
      new Fun(new Integer(), new Open(1), new Integer()),
    );
    return [type_, new Arity2(do_subtract)];
  }

  function do_multiply(left, right, rev, env, k) {
    return require(
      integer(left),
      rev,
      env,
      k,
      (left) => {
        return require(
          integer(right),
          rev,
          env,
          k,
          (right) => {
            return prim(
              new Value(new Integer$1(left * right)),
              rev,
              env,
              k,
            );
          },
        );
      },
    );
  }

  function multiply() {
    let type_ = new Fun(
      new Integer(),
      new Open(0),
      new Fun(new Integer(), new Open(1), new Integer()),
    );
    return [type_, new Arity2(do_multiply)];
  }

  function do_divide(left, right, rev, env, k) {
    return require(
      integer(left),
      rev,
      env,
      k,
      (left) => {
        return require(
          integer(right),
          rev,
          env,
          k,
          (right) => {
            return prim(
              new Value(new Integer$1(divideInt(left, right))),
              rev,
              env,
              k,
            );
          },
        );
      },
    );
  }

  function divide() {
    let type_ = new Fun(
      new Integer(),
      new Open(0),
      new Fun(new Integer(), new Open(1), new Integer()),
    );
    return [type_, new Arity2(do_divide)];
  }

  function do_absolute(x, rev, env, k) {
    return require(
      integer(x),
      rev,
      env,
      k,
      (x) => {
        return prim(
          new Value(new Integer$1(absolute_value(x))),
          rev,
          env,
          k,
        );
      },
    );
  }

  function absolute() {
    let type_ = new Fun(new Integer(), new Open(0), new Integer());
    return [type_, new Arity1(do_absolute)];
  }

  function do_parse(raw, rev, env, k) {
    return require(
      string$1(raw),
      rev,
      env,
      k,
      (raw) => {
        let _pipe = (() => {
          let $ = parse$1(raw);
          if ($.isOk()) {
            let i = $[0];
            return ok(new Integer$1(i));
          } else if (!$.isOk() && !$[0]) {
            return error(unit$1);
          } else {
            throw makeError(
              "case_no_match",
              "harness/ffi/integer",
              71,
              "",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        let _pipe$1 = new Value(_pipe);
        return prim(_pipe$1, rev, env, k);
      },
    );
  }

  function parse() {
    let type_ = new Fun(new Str(), new Open(0), new Integer());
    return [type_, new Arity1(do_parse)];
  }

  function do_to_string(x, rev, env, k) {
    return require(
      integer(x),
      rev,
      env,
      k,
      (x) => {
        return prim(new Value(new Str$1(to_string$7(x))), rev, env, k);
      },
    );
  }

  function to_string() {
    let type_ = new Fun(new Integer(), new Open(0), new Str());
    return [type_, new Arity1(do_to_string)];
  }

  function do_pop(term, rev, env, k) {
    return require(
      list(term),
      rev,
      env,
      k,
      (elements) => {
        let return$ = (() => {
          if (elements.hasLength(0)) {
            return error(unit$1);
          } else if (elements.atLeastLength(1)) {
            let head = elements.head;
            let tail = elements.tail;
            return ok(
              new Record$1(
                toList([["head", head], ["tail", new LinkedList$1(tail)]]),
              ),
            );
          } else {
            throw makeError(
              "case_no_match",
              "harness/ffi/linked_list",
              20,
              "",
              "No case clause matched",
              { values: [elements] }
            )
          }
        })();
        return prim(new Value(return$), rev, env, k);
      },
    );
  }

  function pop() {
    let parts = new Record(
      new Extend(
        "head",
        new Unbound(0),
        new Extend(
          "tail",
          new LinkedList(new Unbound(0)),
          new Closed(),
        ),
      ),
    );
    let type_ = new Fun(
      new LinkedList(new Unbound(0)),
      new Open(1),
      result(parts, unit),
    );
    return [type_, new Arity1(do_pop)];
  }

  function do_fold(elements, state, f, rev, env, k) {
    if (elements.hasLength(0)) {
      return prim(new Value(state), rev, env, k);
    } else if (elements.atLeastLength(1)) {
      let element = elements.head;
      let rest = elements.tail;
      return step_call(
        f,
        element,
        rev,
        env,
        new Some(
          new Kont(
            new CallWith(state, rev, env),
            new Some(
              new Kont(
                new Apply(
                  new Defunc(
                    new Builtin("list_fold"),
                    toList([new LinkedList$1(rest)]),
                  ),
                  rev,
                  env,
                ),
                new Some(new Kont(new CallWith(f, rev, env), k)),
              ),
            ),
          ),
        ),
      );
    } else {
      throw makeError(
        "case_no_match",
        "harness/ffi/linked_list",
        56,
        "do_fold",
        "No case clause matched",
        { values: [elements] }
      )
    }
  }

  function fold_impl(list$1, initial, func, rev, env, k) {
    return require(
      list(list$1),
      rev,
      env,
      k,
      (elements) => { return do_fold(elements, initial, func, rev, env, k); },
    );
  }

  function fold() {
    let type_ = new Fun(
      new LinkedList(new Unbound(-7)),
      new Open(-8),
      new Fun(
        new Unbound(-9),
        new Open(-10),
        new Fun(
          new Fun(
            new Unbound(-7),
            new Open(-11),
            new Fun(new Unbound(-9), new Open(-12), new Unbound(-9)),
          ),
          new Open(-13),
          new Unbound(-9),
        ),
      ),
    );
    return [type_, new Arity3(fold_impl)];
  }

  function do_append(left, right, rev, env, k) {
    return require(
      string$1(left),
      rev,
      env,
      k,
      (left) => {
        return require(
          string$1(right),
          rev,
          env,
          k,
          (right) => {
            return prim(
              new Value(new Str$1(append$2(left, right))),
              rev,
              env,
              k,
            );
          },
        );
      },
    );
  }

  function append() {
    let type_ = new Fun(
      new Str(),
      new Open(0),
      new Fun(new Str(), new Open(1), new Str()),
    );
    return [type_, new Arity2(do_append)];
  }

  function do_split(s, pattern, rev, env, k) {
    return require(
      string$1(s),
      rev,
      env,
      k,
      (s) => {
        return require(
          string$1(pattern),
          rev,
          env,
          k,
          (pattern) => {
            let $ = split$2(s, pattern);
            if (!$.atLeastLength(1)) {
              throw makeError(
                "assignment_no_match",
                "harness/ffi/string",
                27,
                "",
                "Assignment pattern did not match",
                { value: $ }
              )
            }
            let first = $.head;
            let parts = $.tail;
            let parts$1 = new LinkedList$1(
              map$1(parts, (var0) => { return new Str$1(var0); }),
            );
            return prim(
              new Value(
                new Record$1(
                  toList([["head", new Str$1(first)], ["tail", parts$1]]),
                ),
              ),
              rev,
              env,
              k,
            );
          },
        );
      },
    );
  }

  function split() {
    let type_ = new Fun(
      new Str(),
      new Open(0),
      new Fun(new Str(), new Open(1), new LinkedList(new Str())),
    );
    return [type_, new Arity2(do_split)];
  }

  function do_split_once(s, pattern, rev, env, k) {
    return require(
      string$1(s),
      rev,
      env,
      k,
      (s) => {
        return require(
          string$1(pattern),
          rev,
          env,
          k,
          (pattern) => {
            let value = (() => {
              let $ = split_once$1(s, pattern);
              if ($.isOk()) {
                let pre = $[0][0];
                let post = $[0][1];
                return ok(
                  new Record$1(
                    toList([["pre", new Str$1(pre)], ["post", new Str$1(post)]]),
                  ),
                );
              } else if (!$.isOk() && !$[0]) {
                return error(unit$1);
              } else {
                throw makeError(
                  "case_no_match",
                  "harness/ffi/string",
                  47,
                  "",
                  "No case clause matched",
                  { values: [$] }
                )
              }
            })();
            return prim(new Value(value), rev, env, k);
          },
        );
      },
    );
  }

  function split_once() {
    let type_ = new Fun(
      new Str(),
      new Open(0),
      new Fun(new Str(), new Open(1), new LinkedList(new Str())),
    );
    return [type_, new Arity2(do_split_once)];
  }

  function do_uppercase(value, rev, env, k) {
    return require(
      string$1(value),
      rev,
      env,
      k,
      (value) => {
        return prim(
          new Value(new Str$1(uppercase$2(value))),
          rev,
          env,
          k,
        );
      },
    );
  }

  function uppercase() {
    let type_ = new Fun(new Str(), new Open(0), new Str());
    return [type_, new Arity1(do_uppercase)];
  }

  function do_lowercase(value, rev, env, k) {
    return require(
      string$1(value),
      rev,
      env,
      k,
      (value) => {
        return prim(
          new Value(new Str$1(lowercase$2(value))),
          rev,
          env,
          k,
        );
      },
    );
  }

  function lowercase() {
    let type_ = new Fun(new Str(), new Open(0), new Str());
    return [type_, new Arity1(do_lowercase)];
  }

  function do_starts_with(value, prefix, rev, env, k) {
    return require(
      string$1(value),
      rev,
      env,
      k,
      (value) => {
        return require(
          string$1(prefix),
          rev,
          env,
          k,
          (prefix) => {
            let ret = (() => {
              let $ = split_once$1(value, prefix);
              if ($.isOk() && $[0][0] === "") {
                let post = $[0][1];
                return ok(new Str$1(post));
              } else {
                return error(unit$1);
              }
            })();
            return prim(new Value(ret), rev, env, k);
          },
        );
      },
    );
  }

  function starts_with() {
    let type_ = new Fun(
      new Str(),
      new Open(0),
      new Fun(new Str(), new Open(1), result(new Str(), unit)),
    );
    return [type_, new Arity2(do_starts_with)];
  }

  function do_ends_with(value, suffix, rev, env, k) {
    return require(
      string$1(value),
      rev,
      env,
      k,
      (value) => {
        return require(
          string$1(suffix),
          rev,
          env,
          k,
          (suffix) => {
            let ret = (() => {
              let $ = split_once$1(value, suffix);
              if ($.isOk() && $[0][1] === "") {
                let pre = $[0][0];
                return ok(new Str$1(pre));
              } else {
                return error(unit$1);
              }
            })();
            return prim(new Value(ret), rev, env, k);
          },
        );
      },
    );
  }

  function ends_with() {
    let type_ = new Fun(
      new Str(),
      new Open(0),
      new Fun(new Str(), new Open(1), result(new Str(), unit)),
    );
    return [type_, new Arity2(do_ends_with)];
  }

  function do_length(value, rev, env, k) {
    return require(
      string$1(value),
      rev,
      env,
      k,
      (value) => {
        return prim(
          new Value(new Integer$1(length$2(value))),
          rev,
          env,
          k,
        );
      },
    );
  }

  function length() {
    let type_ = new Fun(new Str(), new Open(0), new Integer());
    return [type_, new Arity1(do_length)];
  }

  function do_pop_grapheme(term, rev, env, k) {
    return require(
      string$1(term),
      rev,
      env,
      k,
      (string) => {
        let return$ = (() => {
          let $ = pop_grapheme$2(string);
          if (!$.isOk() && !$[0]) {
            return error(unit$1);
          } else if ($.isOk()) {
            let head = $[0][0];
            let tail = $[0][1];
            return ok(
              new Record$1(
                toList([["head", new Str$1(head)], ["tail", new Str$1(tail)]]),
              ),
            );
          } else {
            throw makeError(
              "case_no_match",
              "harness/ffi/string",
              126,
              "",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        return prim(new Value(return$), rev, env, k);
      },
    );
  }

  function pop_grapheme() {
    let parts = new Record(
      new Extend(
        "head",
        new Str(),
        new Extend("tail", new Str(), new Closed()),
      ),
    );
    let type_ = new Fun(
      new Str(),
      new Open(1),
      result(parts, unit),
    );
    return [type_, new Arity1(do_pop_grapheme)];
  }

  function do_replace(in$, from, to, rev, env, k) {
    return require(
      string$1(in$),
      rev,
      env,
      k,
      (in$) => {
        return require(
          string$1(from),
          rev,
          env,
          k,
          (from) => {
            return require(
              string$1(to),
              rev,
              env,
              k,
              (to) => {
                return prim(
                  new Value(new Str$1(replace$2(in$, from, to))),
                  rev,
                  env,
                  k,
                );
              },
            );
          },
        );
      },
    );
  }

  function replace() {
    let type_ = new Fun(
      new Str(),
      new Open(0),
      new Fun(
        new Str(),
        new Open(1),
        new Fun(new Str(), new Open(1), new Str()),
      ),
    );
    return [type_, new Arity3(do_replace)];
  }

  class DoBody extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class DoFunc extends CustomType$1 {}

  class DoArg extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class DoValue extends CustomType$1 {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class DoThen extends CustomType$1 {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  function do_equal(left, right, rev, env, k) {
    let _pipe = (() => {
      let $ = isEqual(left, right);
      if ($) {
        return true$;
      } else if (!$) {
        return false$;
      } else {
        throw makeError(
          "case_no_match",
          "harness/ffi/core",
          27,
          "do_equal",
          "No case clause matched",
          { values: [$] }
        )
      }
    })();
    let _pipe$1 = new Value(_pipe);
    return prim(_pipe$1, rev, env, k);
  }

  function equal() {
    let type_ = new Fun(
      new Unbound(0),
      new Open(1),
      new Fun(new Unbound(0), new Open(2), boolean),
    );
    return [type_, new Arity2(do_equal)];
  }

  function do_debug(term, rev, env, k) {
    return prim(new Value(new Str$1(to_string$2(term))), rev, env, k);
  }

  function debug() {
    let type_ = new Fun(new Unbound(0), new Open(1), new Str());
    return [type_, new Arity1(do_debug)];
  }

  function do_fix(builder, rev, env, k) {
    return step_call(
      builder,
      new Defunc(new Builtin("fixed"), toList([builder])),
      rev,
      env,
      k,
    );
  }

  function fix() {
    let type_ = new Fun(
      new Fun(new Unbound(-1), new Open(-2), new Unbound(-1)),
      new Open(-3),
      new Unbound(-1),
    );
    return [type_, new Arity1(do_fix)];
  }

  function fixed() {
    return [
      new Unbound(0),
      new Arity2(
        (builder, arg, rev, env, k) => {
          return step_call(
            builder,
            new Defunc(new Builtin("fixed"), toList([builder])),
            rev,
            env,
            new Some(new Kont(new CallWith(arg, rev, env), k)),
          );
        },
      ),
    ];
  }

  function expression_to_language(exp) {
    if (exp instanceof Variable) {
      let label = exp.label;
      return toList([new Tagged("Variable", new Str$1(label))]);
    } else if (exp instanceof Lambda) {
      let label = exp.label;
      let body = exp.body;
      let head = new Tagged("Lambda", new Str$1(label));
      let rest = expression_to_language(body);
      return toList([head], rest);
    } else if (exp instanceof Apply$1) {
      let func = exp.func;
      let argument = exp.argument;
      let head = new Tagged("Apply", new Record$1(toList([])));
      let rest = append$3(
        expression_to_language(func),
        expression_to_language(argument),
      );
      return toList([head], rest);
    } else if (exp instanceof Let) {
      let label = exp.label;
      let definition = exp.definition;
      let body = exp.body;
      let head = new Tagged("Let", new Str$1(label));
      return toList(
        [head],
        append$3(
          expression_to_language(definition),
          expression_to_language(body),
        ),
      );
    } else if (exp instanceof Binary$2) {
      let value = exp.value;
      return toList([new Tagged("Binary", new Binary$1(value))]);
    } else if (exp instanceof Integer$3) {
      let value = exp.value;
      return toList([new Tagged("Integer", new Integer$1(value))]);
    } else if (exp instanceof Str$2) {
      let value = exp.value;
      return toList([new Tagged("String", new Str$1(value))]);
    } else if (exp instanceof Tail) {
      return toList([new Tagged("Tail", new Record$1(toList([])))]);
    } else if (exp instanceof Cons$1) {
      return toList([new Tagged("Cons", new Record$1(toList([])))]);
    } else if (exp instanceof Vacant$1) {
      let comment = exp.comment;
      return toList([new Tagged("Vacant", new Str$1(comment))]);
    } else if (exp instanceof Empty) {
      return toList([new Tagged("Empty", new Record$1(toList([])))]);
    } else if (exp instanceof Extend$2) {
      let label = exp.label;
      return toList([new Tagged("Extend", new Str$1(label))]);
    } else if (exp instanceof Select$1) {
      let label = exp.label;
      return toList([new Tagged("Select", new Str$1(label))]);
    } else if (exp instanceof Overwrite$1) {
      let label = exp.label;
      return toList([new Tagged("Overwrite", new Str$1(label))]);
    } else if (exp instanceof Tag$1) {
      let label = exp.label;
      return toList([new Tagged("Tag", new Str$1(label))]);
    } else if (exp instanceof Case) {
      let label = exp.label;
      return toList([new Tagged("Case", new Str$1(label))]);
    } else if (exp instanceof NoCases$1) {
      return toList([new Tagged("NoCases", new Record$1(toList([])))]);
    } else if (exp instanceof Perform$1) {
      let label = exp.label;
      return toList([new Tagged("Perform", new Str$1(label))]);
    } else if (exp instanceof Handle$1) {
      let label = exp.label;
      return toList([new Tagged("Handle", new Str$1(label))]);
    } else if (exp instanceof Shallow$1) {
      let label = exp.label;
      return toList([new Tagged("Shallow", new Str$1(label))]);
    } else if (exp instanceof Builtin$2) {
      let identifier = exp.identifier;
      return toList([new Tagged("Builtin", new Str$1(identifier))]);
    } else {
      throw makeError(
        "case_no_match",
        "harness/ffi/core",
        246,
        "expression_to_language",
        "No case clause matched",
        { values: [exp] }
      )
    }
  }

  function apply(loop$exp, loop$stack) {
    while (true) {
      let exp = loop$exp;
      let stack = loop$stack;
      if (stack.hasLength(0)) {
        return new Ok$1(exp);
      } else if (stack.atLeastLength(1) && stack.head instanceof DoBody) {
        let label = stack.head[0];
        let stack$1 = stack.tail;
        loop$exp = new Lambda(label, exp);
        loop$stack = stack$1;
      } else if (stack.atLeastLength(1) && stack.head instanceof DoFunc) {
        let stack$1 = stack.tail;
        return new Error$1(toList([new DoArg(exp)], stack$1));
      } else if (stack.atLeastLength(1) && stack.head instanceof DoArg) {
        let func = stack.head[0];
        let stack$1 = stack.tail;
        loop$exp = new Apply$1(func, exp);
        loop$stack = stack$1;
      } else if (stack.atLeastLength(1) && stack.head instanceof DoValue) {
        let label = stack.head[0];
        let stack$1 = stack.tail;
        return new Error$1(toList([new DoThen(label, exp)], stack$1));
      } else if (stack.atLeastLength(1) && stack.head instanceof DoThen) {
        let label = stack.head[0];
        let value = stack.head[1];
        let stack$1 = stack.tail;
        loop$exp = new Let(label, value, exp);
        loop$stack = stack$1;
      } else {
        throw makeError(
          "case_no_match",
          "harness/ffi/core",
          319,
          "apply",
          "No case clause matched",
          { values: [stack] }
        )
      }
    }
  }

  function step(node, stack) {
    if (node instanceof Tagged &&
    node.label === "Variable" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Variable(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Lambda" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new None(), toList([new DoBody(label)], stack)];
    } else if (node instanceof Tagged &&
    node.label === "Apply" &&
    node.value instanceof Record$1 &&
    node.value.fields.hasLength(0)) {
      return [new None(), toList([new DoFunc()], stack)];
    } else if (node instanceof Tagged &&
    node.label === "Let" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new None(), toList([new DoValue(label)], stack)];
    } else if (node instanceof Tagged &&
    node.label === "Integer" &&
    node.value instanceof Integer$1) {
      let value = node.value.value;
      return [new Some(new Integer$3(value)), stack];
    } else if (node instanceof Tagged &&
    node.label === "String" &&
    node.value instanceof Str$1) {
      let value = node.value.value;
      return [new Some(new Str$2(value)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Binary" &&
    node.value instanceof Binary$1) {
      let value = node.value.value;
      return [new Some(new Binary$2(value)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Tail" &&
    node.value instanceof Record$1 &&
    node.value.fields.hasLength(0)) {
      return [new Some(new Tail()), stack];
    } else if (node instanceof Tagged &&
    node.label === "Cons" &&
    node.value instanceof Record$1 &&
    node.value.fields.hasLength(0)) {
      return [new Some(new Cons$1()), stack];
    } else if (node instanceof Tagged &&
    node.label === "Vacant" &&
    node.value instanceof Str$1) {
      let comment = node.value.value;
      return [new Some(new Vacant$1(comment)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Empty" &&
    node.value instanceof Record$1 &&
    node.value.fields.hasLength(0)) {
      return [new Some(new Empty()), stack];
    } else if (node instanceof Tagged &&
    node.label === "Extend" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Extend$2(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Select" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Select$1(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Overwrite" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Overwrite$1(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Tag" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Tag$1(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Case" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Case(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "NoCases" &&
    node.value instanceof Record$1 &&
    node.value.fields.hasLength(0)) {
      return [new Some(new NoCases$1()), stack];
    } else if (node instanceof Tagged &&
    node.label === "Perform" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Perform$1(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Handle" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Handle$1(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Shallow" &&
    node.value instanceof Str$1) {
      let label = node.value.value;
      return [new Some(new Shallow$1(label)), stack];
    } else if (node instanceof Tagged &&
    node.label === "Builtin" &&
    node.value instanceof Str$1) {
      let identifier = node.value.value;
      return [new Some(new Builtin$2(identifier)), stack];
    } else {
      let remaining = node;
      debug$2(["remaining values", remaining, stack]);
      new Error$1("error debuggin expressions");
      return (() => {
        throw makeError(
          "todo",
          "harness/ffi/core",
          381,
          "step",
          "panic expression evaluated",
          {}
        )
      })()("bad decodeding");
    }
  }

  function stack_language_to_expression(loop$source, loop$stack) {
    while (true) {
      let source = loop$source;
      let stack = loop$stack;
      if (!source.atLeastLength(1)) {
        throw makeError(
          "assignment_no_match",
          "harness/ffi/core",
          304,
          "stack_language_to_expression",
          "Assignment pattern did not match",
          { value: source }
        )
      }
      let node = source.head;
      let source$1 = source.tail;
      let $ = step(node, stack);
      let exp = $[0];
      let stack$1 = $[1];
      if (exp instanceof Some) {
        let exp$1 = exp[0];
        let $1 = apply(exp$1, stack$1);
        if ($1.isOk()) {
          let exp$2 = $1[0];
          return exp$2;
        } else if (!$1.isOk()) {
          let stack$2 = $1[0];
          loop$source = source$1;
          loop$stack = stack$2;
        } else {
          throw makeError(
            "case_no_match",
            "harness/ffi/core",
            308,
            "stack_language_to_expression",
            "No case clause matched",
            { values: [$1] }
          )
        }
      } else if (exp instanceof None) {
        loop$source = source$1;
        loop$stack = stack$1;
      } else {
        throw makeError(
          "case_no_match",
          "harness/ffi/core",
          306,
          "stack_language_to_expression",
          "No case clause matched",
          { values: [exp] }
        )
      }
    }
  }

  function language_to_expression(source) {
    return new Ok$1(stack_language_to_expression(source, toList([])));
  }

  function do_decode_uri_component(term, rev, env, k) {
    return require(
      string$1(term),
      rev,
      env,
      k,
      (unencoded) => {
        return prim(
          new Value(new Str$1(decodeURIComponent(unencoded))),
          rev,
          env,
          k,
        );
      },
    );
  }

  function decode_uri_component() {
    let type_ = new Fun(new Str(), new Open(-1), new Str());
    return [type_, new Arity1(do_decode_uri_component)];
  }

  function do_encode_uri(term, rev, env, k) {
    return require(
      string$1(term),
      rev,
      env,
      k,
      (unencoded) => {
        return prim(
          new Value(new Str$1(encodeURI(unencoded))),
          rev,
          env,
          k,
        );
      },
    );
  }

  function encode_uri() {
    let type_ = new Fun(new Str(), new Open(-1), new Str());
    return [type_, new Arity1(do_encode_uri)];
  }

  function do_base64_encode(term, rev, env, k) {
    return require(
      string$1(term),
      rev,
      env,
      k,
      (unencoded) => {
        return prim(
          new Value(
            new Str$1(
              replace$2(
                encode64(from_string(unencoded), true),
                "\r\n",
                "",
              ),
            ),
          ),
          rev,
          env,
          k,
        );
      },
    );
  }

  function base64_encode() {
    let type_ = new Fun(new Str(), new Open(-1), new Str());
    return [type_, new Arity1(do_base64_encode)];
  }

  function do_binary_from_integers(term, rev, env, k) {
    return require(
      list(term),
      rev,
      env,
      k,
      (parts) => {
        let content = fold$4(
          reverse(parts),
          toBitString([]),
          (acc, el) => {
            if (!(el instanceof Integer$1)) {
              throw makeError(
                "assignment_no_match",
                "harness/ffi/core",
                486,
                "",
                "Assignment pattern did not match",
                { value: el }
              )
            }
            let i = el.value;
            return toBitString([i, acc.buffer]);
          },
        );
        return prim(new Value(new Binary$1(content)), rev, env, k);
      },
    );
  }

  function binary_from_integers() {
    let type_ = new Fun(
      new LinkedList(new Integer()),
      new Open(-1),
      new Binary(),
    );
    return [type_, new Arity1(do_binary_from_integers)];
  }

  function lib$1() {
    let _pipe = init$2();
    let _pipe$1 = extend$2(_pipe, "equal", equal());
    let _pipe$2 = extend$2(_pipe$1, "debug", debug());
    let _pipe$3 = extend$2(_pipe$2, "fix", fix());
    let _pipe$4 = extend$2(_pipe$3, "fixed", fixed());
    let _pipe$5 = extend$2(_pipe$4, "serialize", serialize());
    let _pipe$6 = extend$2(_pipe$5, "capture", capture());
    let _pipe$7 = extend$2(_pipe$6, "encode_uri", encode_uri());
    let _pipe$8 = extend$2(_pipe$7, "decode_uri_component", decode_uri_component());
    let _pipe$9 = extend$2(_pipe$8, "base64_encode", base64_encode());
    let _pipe$10 = extend$2(_pipe$9, "binary_from_integers", binary_from_integers());
    let _pipe$11 = extend$2(_pipe$10, "int_add", add());
    let _pipe$12 = extend$2(_pipe$11, "int_subtract", subtract());
    let _pipe$13 = extend$2(_pipe$12, "int_multiply", multiply());
    let _pipe$14 = extend$2(_pipe$13, "int_divide", divide());
    let _pipe$15 = extend$2(_pipe$14, "int_absolute", absolute());
    let _pipe$16 = extend$2(_pipe$15, "int_parse", parse());
    let _pipe$17 = extend$2(_pipe$16, "int_to_string", to_string());
    let _pipe$18 = extend$2(_pipe$17, "string_append", append());
    let _pipe$19 = extend$2(_pipe$18, "string_split", split());
    let _pipe$20 = extend$2(_pipe$19, "string_split_once", split_once());
    let _pipe$21 = extend$2(_pipe$20, "string_replace", replace());
    let _pipe$22 = extend$2(_pipe$21, "string_uppercase", uppercase());
    let _pipe$23 = extend$2(_pipe$22, "string_lowercase", lowercase());
    let _pipe$24 = extend$2(_pipe$23, "string_starts_with", starts_with());
    let _pipe$25 = extend$2(_pipe$24, "string_ends_with", ends_with());
    let _pipe$26 = extend$2(_pipe$25, "string_length", length());
    let _pipe$27 = extend$2(_pipe$26, "pop_grapheme", pop_grapheme());
    let _pipe$28 = extend$2(_pipe$27, "list_pop", pop());
    let _pipe$29 = extend$2(_pipe$28, "list_fold", fold());
    return extend$2(_pipe$29, "eval", eval$());
  }

  function eval$() {
    let type_ = new Fun(
      new Unbound(-1),
      new Open(-2),
      new Unbound(-3),
    );
    return [type_, new Arity1(do_eval)];
  }

  function do_eval(source, rev, env, k) {
    return require(
      list(source),
      rev,
      env,
      k,
      (source) => {
        let $ = language_to_expression(source);
        if ($.isOk()) {
          let expression = $[0];
          let $1 = eval$$1(
            expression,
            new Env(toList([]), lib$1()[1]),
            new Some(
              new Kont(
                new Apply(
                  new Defunc(new Tag("Ok"), toList([])),
                  rev,
                  env,
                ),
                new None(),
              ),
            ),
          );
          if (!($1 instanceof Value)) {
            throw makeError(
              "assignment_no_match",
              "harness/ffi/core",
              148,
              "",
              "Assignment pattern did not match",
              { value: $1 }
            )
          }
          let value = $1.term;
          return prim(new Value(value), rev, env, k);
        } else if (!$.isOk()) {
          return prim(new Value(error(unit$1)), rev, env, k);
        } else {
          throw makeError(
            "case_no_match",
            "harness/ffi/core",
            145,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      },
    );
  }

  function do_capture(term, rev, env, k) {
    let exp = capture$1(term);
    return prim(
      new Value(new LinkedList$1(expression_to_language(exp))),
      rev,
      env,
      k,
    );
  }

  function capture() {
    let type_ = new Fun(
      new Unbound(-1),
      new Open(-2),
      new Unbound(-3),
    );
    return [type_, new Arity1(do_capture)];
  }

  function do_serialize(term, rev, env, k) {
    let exp = capture$1(term);
    return prim(new Value(new Str$1(to_json(exp))), rev, env, k);
  }

  function serialize() {
    let type_ = new Fun(new Unbound(-1), new Open(-2), new Str());
    return [type_, new Arity1(do_serialize)];
  }

  function empty() {
    return new Env(toList([]), new$$2());
  }

  function wait$1(delay) {
    return newPromise(
      (resolve) => { return setTimeout(resolve, delay); },
    );
  }

  function init$1() {
    return [new Closed(), new$$2()];
  }

  function extend$1(state, label, parts) {
    let eff = state[0];
    let handlers = state[1];
    let from = parts[0];
    let to = parts[1];
    let handler = parts[2];
    let eff$1 = new Extend(label, [from, to], eff);
    let handlers$1 = insert$1(handlers, label, handler);
    return [eff$1, handlers$1];
  }

  function debug_logger() {
    return [
      new Str(),
      unit,
      (message, k) => {
        let env = empty();
        let rev = toList([]);
        print$1(to_string$2(message));
        print$1("\n");
        return prim(new Value(unit$1), rev, env, k);
      },
    ];
  }

  function window_alert() {
    return [
      new Str(),
      unit,
      (message, k) => {
        let env = empty();
        let rev = toList([]);
        return require(
          string$1(message),
          rev,
          env,
          k,
          (message) => {
            alert(message);
            return prim(new Value(unit$1), rev, env, k);
          },
        );
      },
    ];
  }

  function choose() {
    return [
      unit,
      boolean,
      (_, k) => {
        let env = empty();
        let rev = toList([]);
        let value = (() => {
          let $ = random$1(0, 2);
          if ($ === 0) {
            return false$;
          } else if ($ === 1) {
            return true$;
          } else {
            throw makeError(
              "case_no_match",
              "harness/effect",
              72,
              "",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        return prim(new Value(value), rev, env, k);
      },
    ];
  }

  function http() {
    return [
      new Str(),
      unit,
      (request, k) => {
        let env = empty();
        let rev = toList([]);
        return require(
          field("method", any, request),
          rev,
          env,
          k,
          (method) => {
            if (!(method instanceof Tagged)) {
              throw makeError(
                "assignment_no_match",
                "harness/effect",
                94,
                "",
                "Assignment pattern did not match",
                { value: method }
              )
            }
            let method$1 = method.label;
            let method$2 = (() => {
              let $ = uppercase$2(method$1);
              if ($ === "GET") {
                return new Get();
              } else if ($ === "POST") {
                return new Post();
              } else {
                throw makeError(
                  "case_no_match",
                  "harness/effect",
                  95,
                  "",
                  "No case clause matched",
                  { values: [$] }
                )
              }
            })();
            return require(
              field("scheme", any, request),
              rev,
              env,
              k,
              (scheme) => {
                return require(
                  field("host", string$1, request),
                  rev,
                  env,
                  k,
                  (host) => {
                    return require(
                      field("port", any, request),
                      rev,
                      env,
                      k,
                      (port) => {
                        return require(
                          field("path", string$1, request),
                          rev,
                          env,
                          k,
                          (path) => {
                            return require(
                              field("query", any, request),
                              rev,
                              env,
                              k,
                              (query) => {
                                return require(
                                  field("headers", list, request),
                                  rev,
                                  env,
                                  k,
                                  (headers) => {
                                    let $ = try_map(
                                      headers,
                                      (h) => {
                                        return try$(
                                          field$1(h, "key"),
                                          (k) => {
                                            if (!(k instanceof Str$1)) {
                                              throw makeError(
                                                "assignment_no_match",
                                                "harness/effect",
                                                140,
                                                "",
                                                "Assignment pattern did not match",
                                                { value: k }
                                              )
                                            }
                                            let k$1 = k.value;
                                            return try$(
                                              field$1(h, "value"),
                                              (value) => {
                                                if (!(value instanceof Str$1)) {
                                                  throw makeError(
                                                    "assignment_no_match",
                                                    "harness/effect",
                                                    142,
                                                    "",
                                                    "Assignment pattern did not match",
                                                    { value: value }
                                                  )
                                                }
                                                let value$1 = value.value;
                                                return new Ok$1([k$1, value$1]);
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                    if (!$.isOk()) {
                                      throw makeError(
                                        "assignment_no_match",
                                        "harness/effect",
                                        135,
                                        "",
                                        "Assignment pattern did not match",
                                        { value: $ }
                                      )
                                    }
                                    let headers$1 = $[0];
                                    return require(
                                      field("body", any, request),
                                      rev,
                                      env,
                                      k,
                                      (body) => {
                                        if (!(body instanceof Str$1)) {
                                          throw makeError(
                                            "assignment_no_match",
                                            "harness/effect",
                                            155,
                                            "",
                                            "Assignment pattern did not match",
                                            { value: body }
                                          )
                                        }
                                        let body$1 = body.value;
                                        let request$1 = (() => {
                                          let _pipe = new$$1();
                                          let _pipe$1 = set_method(
                                            _pipe,
                                            method$2,
                                          );
                                          let _pipe$2 = set_host(
                                            _pipe$1,
                                            host,
                                          );
                                          let _pipe$3 = set_path(
                                            _pipe$2,
                                            path,
                                          );
                                          return set_body(
                                            _pipe$3,
                                            body$1,
                                          );
                                        })();
                                        let request$2 = fold$4(
                                          headers$1,
                                          request$1,
                                          (req, h) => {
                                            let k$1 = h[0];
                                            let v = h[1];
                                            return set_header(
                                              req,
                                              k$1,
                                              v,
                                            );
                                          },
                                        );
                                        let promise = (() => {
                                          let _pipe = try_await(
                                            send(request$2),
                                            (response) => {
                                              return read_text_body(
                                                response,
                                              );
                                            },
                                          );
                                          return map_promise(
                                            _pipe,
                                            (response) => {
                                              if (response.isOk()) {
                                                let response$1 = response[0];
                                                let resp = ok(
                                                  new Record$1(
                                                    toList([
                                                      [
                                                        "status",
                                                        new Integer$1(
                                                          response$1.status,
                                                        ),
                                                      ],
                                                      [
                                                        "headers",
                                                        new LinkedList$1(
                                                          map$1(
                                                            response$1.headers,
                                                            (h) => {
                                                              let k$1 = h[0];
                                                              let v = h[1];
                                                              return new Record$1(
                                                                toList([
                                                                  [
                                                                    "key",
                                                                    new Str$1(
                                                                      k$1,
                                                                    ),
                                                                  ],
                                                                  [
                                                                    "value",
                                                                    new Str$1(v),
                                                                  ],
                                                                ]),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ],
                                                      [
                                                        "body",
                                                        new Str$1(
                                                          response$1.body,
                                                        ),
                                                      ],
                                                    ]),
                                                  ),
                                                );
                                                return resp;
                                              } else if (!response.isOk()) {
                                                return error(
                                                  new Str$1("bad response"),
                                                );
                                              } else {
                                                throw makeError(
                                                  "case_no_match",
                                                  "harness/effect",
                                                  183,
                                                  "",
                                                  "No case clause matched",
                                                  { values: [response] }
                                                )
                                              }
                                            },
                                          );
                                        })();
                                        return prim(
                                          new Value(new Promise$1(promise)),
                                          rev,
                                          env,
                                          k,
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    ];
  }

  function await$() {
    return [
      new Str(),
      unit,
      (promise$1, k) => {
        let env = empty();
        let rev = toList([]);
        return require(
          promise(promise$1),
          rev,
          env,
          k,
          (js_promise) => {
            return prim(
              new Async(js_promise, rev, env, k),
              rev,
              env,
              new None(),
            );
          },
        );
      },
    ];
  }

  function wait() {
    return [
      new Integer(),
      unit,
      (milliseconds, k) => {
        let env = empty();
        let rev = toList([]);
        return require(
          integer(milliseconds),
          rev,
          env,
          k,
          (milliseconds) => {
            let p = wait$1(milliseconds);
            return prim(
              new Value(
                new Promise$1(map_promise(p, (_) => { return unit$1; })),
              ),
              rev,
              env,
              k,
            );
          },
        );
      },
    ];
  }

  function lib() {
    return lib$1();
  }

  function env() {
    return new Env(toList([]), lib()[1]);
  }

  function render() {
    return [
      new Str(),
      unit,
      (page, k) => {
        let env = empty();
        let rev = toList([]);
        if (!(page instanceof Str$1)) {
          throw makeError(
            "assignment_no_match",
            "platforms/browser",
            134,
            "",
            "Assignment pattern did not match",
            { value: page }
          )
        }
        let page$1 = page.value;
        let $ = querySelector(doc(), "#app");
        if ($.isOk()) {
          let element = $[0];
          setInnerHTML(element, page$1);
        } else {
          throw makeError(
            "todo",
            "platforms/browser",
            138,
            "",
            "could not render as no app element found, the reference to the app element should exist from start time and not be checked on every render",
            {}
          )
        }
        return prim(new Value(unit$1), rev, env, k);
      },
    ];
  }

  function location_search() {
    return [
      unit,
      unit,
      (_, k) => {
        let env = empty();
        let rev = toList([]);
        let value = (() => {
          let $ = locationSearch();
          if ($.isOk()) {
            let str = $[0];
            return ok(new Str$1(str));
          } else if (!$.isOk()) {
            return error(unit$1);
          } else {
            throw makeError(
              "case_no_match",
              "platforms/browser",
              229,
              "",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        return prim(new Value(value), rev, env, k);
      },
    ];
  }

  function do_handle(arg, handle, builtins, extrinsic) {
    let $ = eval$$1(arg, env(), new None());
    if (!($ instanceof Value)) {
      throw makeError(
        "assignment_no_match",
        "platforms/browser",
        277,
        "do_handle",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let arg$1 = $.term;
    let ret = handle$1(
      eval_call(handle, arg$1, builtins, new None()),
      extrinsic,
    );
    if (ret instanceof Value) {
      return undefined;
    } else {
      debug$2(ret);
      return undefined;
    }
  }

  function async() {
    return [
      unit,
      unit,
      (exec, k) => {
        let env$1 = env();
        let rev = toList([]);
        let $ = (() => {
          let _pipe = handlers();
          return extend$1(_pipe, "Await", await$());
        })();
        let extrinsic = $[1];
        let promise = (() => {
          let _pipe = wait$1(0);
          let _pipe$1 = then(
            _pipe,
            (_) => {
              let ret = handle$1(
                eval_call(exec, unit$1, env$1, new None()),
                extrinsic,
              );
              return flatten_promise(ret, extrinsic);
            },
          );
          return map_promise(
            _pipe$1,
            (result) => {
              if (result.isOk()) {
                let term = result[0];
                return term;
              } else if (!result.isOk()) {
                let reason = result[0][0];
                log(reason_to_string$1(reason));
                return (() => {
                  throw makeError(
                    "todo",
                    "platforms/browser",
                    169,
                    "",
                    "panic expression evaluated",
                    {}
                  )
                })()("this shouldn't fail");
              } else {
                throw makeError(
                  "case_no_match",
                  "platforms/browser",
                  164,
                  "",
                  "No case clause matched",
                  { values: [result] }
                )
              }
            },
          );
        })();
        return prim(new Value(new Promise$1(promise)), rev, env$1, k);
      },
    ];
  }

  function handlers() {
    let _pipe = init$1();
    let _pipe$1 = extend$1(_pipe, "Log", debug_logger());
    let _pipe$2 = extend$1(_pipe$1, "Alert", window_alert());
    let _pipe$3 = extend$1(_pipe$2, "HTTP", http());
    let _pipe$4 = extend$1(_pipe$3, "Render", render());
    let _pipe$5 = extend$1(_pipe$4, "Wait", wait());
    let _pipe$6 = extend$1(_pipe$5, "Await", await$());
    let _pipe$7 = extend$1(_pipe$6, "Async", async());
    let _pipe$8 = extend$1(_pipe$7, "Listen", listen());
    let _pipe$9 = extend$1(_pipe$8, "LocationSearch", location_search());
    let _pipe$10 = extend$1(_pipe$9, "OnClick", on_click());
    return extend$1(_pipe$10, "OnKeyDown", on_keydown());
  }

  function listen() {
    return [
      unit,
      unit,
      (sub, k) => {
        let env$1 = empty();
        let rev = toList([]);
        return require(
          field("event", string$1, sub),
          rev,
          env$1,
          k,
          (event) => {
            return require(
              field("handler", any, sub),
              rev,
              env$1,
              k,
              (handle) => {
                let env$1 = env();
                let $ = handlers();
                let extrinsic = $[1];
                addEventListener(
                  event,
                  (_) => {
                    let ret = handle$1(
                      eval_call(handle, unit$1, env$1, new None()),
                      extrinsic,
                    );
                    debug$2(ret);
                    return undefined;
                  },
                );
                return prim(new Value(unit$1), rev, env$1, k);
              },
            );
          },
        );
      },
    ];
  }

  function on_click() {
    return [
      unit,
      unit,
      (handle, k) => {
        let env$1 = env();
        let rev = toList([]);
        let $ = handlers();
        let extrinsic = $[1];
        onClick(
          (arg) => {
            let arg$1 = decodeURI(arg);
            let $1 = from_json(arg$1);
            if (!$1.isOk()) {
              throw makeError(
                "assignment_no_match",
                "platforms/browser",
                252,
                "",
                "Assignment pattern did not match",
                { value: $1 }
              )
            }
            let arg$2 = $1[0];
            return do_handle(arg$2, handle, env$1, extrinsic);
          },
        );
        return prim(new Value(unit$1), rev, env$1, k);
      },
    ];
  }

  function on_keydown() {
    return [
      unit,
      unit,
      (handle, k) => {
        let env$1 = env();
        let rev = toList([]);
        let $ = handlers();
        let extrinsic = $[1];
        onKeyDown(
          (k) => { return do_handle(new Str$2(k), handle, env$1, extrinsic); },
        );
        return prim(new Value(unit$1), rev, env$1, k);
      },
    ];
  }

  class Command extends CustomType$1 {
    constructor(warning) {
      super();
      this.warning = warning;
    }
  }

  class Insert extends CustomType$1 {}

  class Embed extends CustomType$1 {
    constructor(mode, yanked, env, source, history, auto_infer, inferred, returned, rendered, focus) {
      super();
      this.mode = mode;
      this.yanked = yanked;
      this.env = env;
      this.source = source;
      this.history = history;
      this.auto_infer = auto_infer;
      this.inferred = inferred;
      this.returned = returned;
      this.rendered = rendered;
      this.focus = focus;
    }
  }

  function do_infer(source, cache) {
    let sub = cache[1];
    let next = cache[2];
    let tenv = cache[3];
    return infer_env(
      source,
      new Var(-10),
      new Var(-11),
      tenv,
      sub,
      next,
    )[0];
  }

  function nearest_click_handler$1(event) {
    let target$1 = target(event);
    let $ = closest(target$1, "[data-click]");
    if ($.isOk()) {
      let element = $[0];
      let $1 = datasetGet(element, "click");
      if (!$1.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          94,
          "nearest_click_handler",
          "Assignment pattern did not match",
          { value: $1 }
        )
      }
      let handle$1 = $1[0];
      return new Ok$1(handle$1);
    } else if (!$.isOk() && !$[0]) {
      return new Error$1(undefined);
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        91,
        "nearest_click_handler",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function load_source() {
    return try_await(
      showOpenFilePicker(),
      (_use0) => {
        let file_handle = _use0[0];
        return then(
          getFile(file_handle),
          (file) => {
            return map_promise(
              fileText(file),
              (text) => {
                let $ = from_json(text);
                if (!$.isOk()) {
                  throw makeError(
                    "assignment_no_match",
                    "easel/embed",
                    105,
                    "",
                    "Assignment pattern did not match",
                    { value: $ }
                  )
                }
                let source = $[0];
                return new Ok$1(source);
              },
            );
          },
        );
      },
    );
  }

  function init(json) {
    debug$2("init easil");
    let $ = decoder(json);
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        428,
        "init",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let source = $[0];
    let env$1 = env();
    let $1 = infer(source, new Var(-1), new Var(-2));
    let sub = $1[0][0];
    let next = $1[0][1];
    let envs = $1[1];
    let $2 = (() => {
      let $3 = resumable(source, env(), new None());
      if ($3[0] instanceof Value && $3[0].term instanceof Function$1) {
        let source$1 = $3[0].term.body;
        let rev = $3[0].term.path;
        let env$1 = $3[1];
        let tenv = (() => {
          let $4 = get(envs, rev);
          if ($4.isOk()) {
            let tenv = $4[0];
            return tenv;
          } else if (!$4.isOk() && !$4[0]) {
            debug$2(["no env foud at rev", rev]);
            return new$$2();
          } else {
            throw makeError(
              "case_no_match",
              "easel/embed",
              436,
              "init",
              "No case clause matched",
              { values: [$4] }
            )
          }
        })();
        return [env$1, source$1, sub, next, tenv];
      } else {
        return [env$1, source, new$$2(), 0, new$$2()];
      }
    })();
    let env$1$1 = $2[0];
    let source$1 = $2[1];
    let sub$1 = $2[2];
    let next$1 = $2[3];
    let tenv = $2[4];
    let cache = [env$1$1, sub$1, next$1, tenv];
    let inferred = do_infer(source$1, cache);
    let rendered = print(source$1, new None(), true, new Some(inferred));
    return new Embed(
      new Command(""),
      new None(),
      cache,
      source$1,
      [toList([]), toList([])],
      true,
      new Some(inferred),
      new None(),
      rendered,
      new None(),
    );
  }

  function is_var(value) {
    let $ = from_string$2("^[a-z_]$");
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        467,
        "is_var",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let re = $[0];
    if (value === "") {
      return true;
    } else {
      return check(re, value);
    }
  }

  function is_tag(value) {
    let $ = from_string$2("^[A-Za-z]$");
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        475,
        "is_tag",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let re = $[0];
    if (value === "") {
      return true;
    } else {
      return check(re, value);
    }
  }

  function is_num(value) {
    return is_ok(parse$1(value));
  }

  function reason_to_string(reason) {
    return reason_to_string$1(reason);
  }

  function term_to_string(term) {
    return to_string$2(term);
  }

  function run$1(state) {
    let $ = window_alert();
    let handler = $[2];
    let source = state.source;
    let $1 = state.env;
    let env = $1[0];
    let handlers = (() => {
      let _pipe = new$$2();
      let _pipe$1 = insert$1(_pipe, "Alert", handler);
      let _pipe$2 = insert$1(_pipe$1, "Choose", choose()[2]);
      let _pipe$3 = insert$1(_pipe$2, "HTTP", http()[2]);
      let _pipe$4 = insert$1(_pipe$3, "Await", await$()[2]);
      let _pipe$5 = insert$1(_pipe$4, "Async", async()[2]);
      return insert$1(_pipe$5, "Log", debug_logger()[2]);
    })();
    let ret = handle$1(eval$$1(source, env, new None()), handlers);
    if (ret instanceof Abort) {
      let reason = ret.reason;
      return [reason_to_string(reason), toList([])];
    } else if (ret instanceof Value) {
      let term = ret.term;
      return [term_to_string(term), toList([])];
    } else if (ret instanceof Async) {
      let p = map_promise(
        flatten_promise(ret, handlers),
        (final) => {
          let message = (() => {
            if (!final.isOk()) {
              let reason = final[0][0];
              return reason_to_string(reason);
            } else if (final.isOk()) {
              let term = final[0];
              debug$2(term);
              return term_to_string(term);
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                952,
                "",
                "No case clause matched",
                { values: [final] }
              )
            }
          })();
          return (state) => {
            return state.withFields({ mode: new Command(message) });
          };
        },
      );
      return ["Running", toList([p])];
    } else {
      return (() => {
        throw makeError(
          "todo",
          "easel/embed",
          965,
          "run",
          "panic expression evaluated",
          {}
        )
      })()("this should be tackled better in the run code");
    }
  }

  function undo(state, start) {
    let $ = at$1(state.rendered[0], start);
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        978,
        "undo",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let current_path = $[0][1];
    let $1 = state.history[1];
    if ($1.hasLength(0)) {
      return [
        state.withFields({ mode: new Command("no undo available") }),
        start,
        toList([]),
      ];
    } else if ($1.atLeastLength(1)) {
      let edit = $1.head;
      let backwards = $1.tail;
      let old = edit[0];
      let path = edit[1];
      let text_only = edit[2];
      let inferred = (() => {
        let $2 = state.auto_infer;
        if ($2) {
          return new Some(do_infer(old, state.env));
        } else if (!$2) {
          return new None();
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            985,
            "undo",
            "No case clause matched",
            { values: [$2] }
          )
        }
      })();
      let rendered = print(old, state.focus, state.auto_infer, inferred);
      let $2 = get(rendered[1], path_to_string(path));
      if (!$2.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          990,
          "undo",
          "Assignment pattern did not match",
          { value: $2 }
        )
      }
      let start$1 = $2[0];
      let state$1 = state.withFields({
        mode: new Command(""),
        source: old,
        history: [
          toList([[state.source, current_path, text_only]], state.history[0]),
          backwards,
        ],
        inferred: inferred,
        rendered: rendered
      });
      return [state$1, start$1, toList([])];
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        980,
        "undo",
        "No case clause matched",
        { values: [$1] }
      )
    }
  }

  function redo(state, start) {
    let $ = at$1(state.rendered[0], start);
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        1010,
        "redo",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let current_path = $[0][1];
    let $1 = state.history[0];
    if ($1.hasLength(0)) {
      return [
        state.withFields({ mode: new Command("no redo available") }),
        start,
        toList([]),
      ];
    } else if ($1.atLeastLength(1)) {
      let edit = $1.head;
      let forward = $1.tail;
      let other = edit[0];
      let path = edit[1];
      let text_only = edit[2];
      let inferred = (() => {
        let $2 = state.auto_infer;
        if ($2) {
          return new Some(do_infer(other, state.env));
        } else if (!$2) {
          return new None();
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            1016,
            "redo",
            "No case clause matched",
            { values: [$2] }
          )
        }
      })();
      let rendered = print(other, state.focus, state.auto_infer, inferred);
      let $2 = get(rendered[1], path_to_string(path));
      if (!$2.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          1021,
          "redo",
          "Assignment pattern did not match",
          { value: $2 }
        )
      }
      let start$1 = $2[0];
      let state$1 = state.withFields({
        mode: new Command(""),
        source: other,
        history: [
          forward,
          toList([[state.source, current_path, text_only]], state.history[1]),
        ],
        inferred: inferred,
        rendered: rendered
      });
      return [state$1, start$1, toList([])];
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        1012,
        "redo",
        "No case clause matched",
        { values: [$1] }
      )
    }
  }

  function update_selection(state, start, end) {
    let $ = at$1(state.rendered[0], start);
    if (!$.isOk() && !$[0]) {
      return state.withFields({ focus: new None() });
    } else if ($.isOk()) {
      let path = $[0][1];
      let $1 = at$1(state.rendered[0], end);
      if (!$1.isOk() && !$1[0]) {
        return state.withFields({ focus: new None() });
      } else if ($1.isOk()) {
        let p2 = $1[0][1];
        let $2 = !isEqual(path, p2);
        if ($2) {
          return state.withFields({ focus: new None() });
        } else if (!$2) {
          return state.withFields({ focus: new Some(path) });
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            1300,
            "update_selection",
            "No case clause matched",
            { values: [$2] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "easel/embed",
          1297,
          "update_selection",
          "No case clause matched",
          { values: [$1] }
        )
      }
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        1294,
        "update_selection",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function do_group(loop$rest, loop$current, loop$acc, loop$style, loop$err) {
    while (true) {
      let rest = loop$rest;
      let current = loop$current;
      let acc = loop$acc;
      let style = loop$style;
      let err = loop$err;
      if (rest.hasLength(0)) {
        return reverse(toList([[style, err, reverse(current)]], acc));
      } else if (rest.atLeastLength(1)) {
        let ch = rest.head[0];
        let s = rest.head[3];
        let e = rest.head[4];
        let rest$1 = rest.tail;
        let $ = (isEqual(s, style)) && (isEqual(e, err));
        if ($) {
          loop$rest = rest$1;
          loop$current = toList([ch], current);
          loop$acc = acc;
          loop$style = style;
          loop$err = err;
        } else if (!$) {
          loop$rest = rest$1;
          loop$current = toList([ch]);
          loop$acc = toList([[style, err, reverse(current)]], acc);
          loop$style = s;
          loop$err = e;
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            1393,
            "do_group",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "easel/embed",
          1390,
          "do_group",
          "No case clause matched",
          { values: [rest] }
        )
      }
    }
  }

  function group(rendered) {
    if (rendered.hasLength(0)) {
      return toList([]);
    } else if (rendered.atLeastLength(1)) {
      let ch = rendered.head[0];
      let style = rendered.head[3];
      let err = rendered.head[4];
      let rendered$1 = rendered.tail;
      return do_group(rendered$1, toList([ch]), toList([]), style, err);
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        1382,
        "group",
        "No case clause matched",
        { values: [rendered] }
      )
    }
  }

  function escape(state) {
    return state.withFields({ mode: new Command("") });
  }

  function blur(state) {
    return escape(state);
  }

  function single_focus(state, start, end, cb) {
    let $ = at$1(state.rendered[0], start);
    if (!$.isOk() && !$[0]) {
      return [state, start, toList([])];
    } else if ($.isOk()) {
      let path = $[0][1];
      let $1 = at$1(state.rendered[0], end);
      if (!$1.isOk() && !$1[0]) {
        return [state, start, toList([])];
      } else if ($1.isOk()) {
        let p2 = $1[0][1];
        let $2 = !isEqual(path, p2);
        if ($2) {
          return [state, start, toList([])];
        } else if (!$2) {
          return cb(path);
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            1422,
            "single_focus",
            "No case clause matched",
            { values: [$2] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "easel/embed",
          1419,
          "single_focus",
          "No case clause matched",
          { values: [$1] }
        )
      }
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        1416,
        "single_focus",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function copy(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        let $ = at(state.source, path);
        if (!$.isOk() && !$[0]) {
          return (() => {
            throw makeError(
              "todo",
              "easel/embed",
              1097,
              "",
              "panic expression evaluated",
              {}
            )
          })()("how did this happen need path back");
        } else if ($.isOk()) {
          let target = $[0][0];
          return [
            state.withFields({ yanked: new Some(target) }),
            start,
            toList([]),
          ];
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            1096,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      },
    );
  }

  function update_at(state, path, cb) {
    let source = state.source;
    let $ = at(source, path);
    if (!$.isOk() && !$[0]) {
      return (() => {
        throw makeError(
          "todo",
          "easel/embed",
          1436,
          "update_at",
          "panic expression evaluated",
          {}
        )
      })()("how did this happen need path back");
    } else if ($.isOk()) {
      let target = $[0][0];
      let rezip = $[0][1];
      let $1 = cb(target);
      let updated = $1[0];
      let mode = $1[1];
      let sub_path = $1[2];
      let new$ = rezip(updated);
      let history = [
        toList([]),
        toList([[source, path, false]], state.history[1]),
      ];
      let inferred = (() => {
        let $2 = state.auto_infer;
        if ($2) {
          return new Some(do_infer(new$, state.env));
        } else if (!$2) {
          return new None();
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            1441,
            "update_at",
            "No case clause matched",
            { values: [$2] }
          )
        }
      })();
      let rendered = print(new$, state.focus, state.auto_infer, inferred);
      let path$1 = append$3(path, sub_path);
      let $2 = get(rendered[1], path_to_string(path$1));
      if (!$2.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          1447,
          "update_at",
          "Assignment pattern did not match",
          { value: $2 }
        )
      }
      let start = $2[0];
      return [
        state.withFields({
          mode: mode,
          source: new$,
          history: history,
          inferred: inferred,
          rendered: rendered
        }),
        start,
        toList([]),
      ];
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        1435,
        "update_at",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function builtin(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            if (target instanceof Vacant$1) {
              return [new Builtin$2(""), new Insert(), toList([])];
            } else {
              return [
                new Apply$1(new Builtin$2(""), target),
                new Insert(),
                toList([0]),
              ];
            }
          },
        );
      },
    );
  }

  function call_with(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Apply$1(new Vacant$1(""), target),
              state.mode,
              toList([0]),
            ];
          },
        );
      },
    );
  }

  function assign_to(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Let("", target, new Vacant$1("")),
              new Insert(),
              toList([]),
            ];
          },
        );
      },
    );
  }

  function assign_before(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Let("", new Vacant$1(""), target),
              new Insert(),
              toList([]),
            ];
          },
        );
      },
    );
  }

  function extend(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            if (target instanceof Vacant$1 && target.comment === "") {
              return [new Empty(), state.mode, toList([])];
            } else {
              return [
                new Apply$1(
                  new Apply$1(new Extend$2(""), new Vacant$1("")),
                  target,
                ),
                new Insert(),
                toList([]),
              ];
            }
          },
        );
      },
    );
  }

  function extender(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (_) => { return [new Extend$2(""), state.mode, toList([])]; },
        );
      },
    );
  }

  function tag(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Apply$1(new Tag$1(""), target),
              new Insert(),
              toList([0]),
            ];
          },
        );
      },
    );
  }

  function paste(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [unwrap(state.yanked, target), state.mode, toList([])];
          },
        );
      },
    );
  }

  function overwrite(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Apply$1(
                new Apply$1(new Overwrite$1(""), new Vacant$1("")),
                target,
              ),
              new Insert(),
              toList([]),
            ];
          },
        );
      },
    );
  }

  function perform(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            if (target instanceof Vacant$1) {
              return [new Perform$1(""), new Insert(), toList([])];
            } else {
              return [
                new Apply$1(new Perform$1(""), target),
                new Insert(),
                toList([0]),
              ];
            }
          },
        );
      },
    );
  }

  function string(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (_) => { return [new Str$2(""), new Insert(), toList([])]; },
        );
      },
    );
  }

  function replace_at(label, start, end, data) {
    let start$1 = min(length$2(label), start);
    let label$1 = replace_at$1(label, start$1, end, data);
    return [label$1, start$1 + length$2(data)];
  }

  function binary(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (_) => {
            return [
              new Binary$2(toBitString([1, 10, 100])),
              new Insert(),
              toList([]),
            ];
          },
        );
      },
    );
  }

  function delete$(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            if (target instanceof Let) {
              let then$ = target.body;
              return [then$, state.mode, toList([])];
            } else if (target instanceof Apply$1 &&
            target.func instanceof Apply$1 &&
            target.func.func instanceof Cons$1) {
              let rest = target.argument;
              return [rest, state.mode, toList([])];
            } else if (target instanceof Apply$1 &&
            target.func instanceof Apply$1 &&
            target.func.func instanceof Extend$2) {
              let rest = target.argument;
              return [rest, state.mode, toList([])];
            } else if (target instanceof Apply$1 &&
            target.func instanceof Apply$1 &&
            target.func.func instanceof Overwrite$1) {
              let rest = target.argument;
              return [rest, state.mode, toList([])];
            } else if (target instanceof Apply$1 &&
            target.func instanceof Apply$1 &&
            target.func.func instanceof Case) {
              let then$ = target.argument;
              return [then$, state.mode, toList([])];
            } else {
              return [new Vacant$1(""), state.mode, toList([])];
            }
          },
        );
      },
    );
  }

  function insert_function(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [new Lambda("", target), new Insert(), toList([])];
          },
        );
      },
    );
  }

  function select(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Apply$1(new Select$1(""), target),
              new Insert(),
              toList([0]),
            ];
          },
        );
      },
    );
  }

  function handle(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            if (target instanceof Vacant$1) {
              return [new Handle$1(""), new Insert(), toList([])];
            } else {
              return [
                new Apply$1(new Handle$1(""), target),
                new Insert(),
                toList([0]),
              ];
            }
          },
        );
      },
    );
  }

  function shallow(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            if (target instanceof Vacant$1) {
              return [new Shallow$1(""), new Insert(), toList([])];
            } else {
              return [
                new Apply$1(new Shallow$1(""), target),
                new Insert(),
                toList([0]),
              ];
            }
          },
        );
      },
    );
  }

  function list_element(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            let new$ = (() => {
              if (target instanceof Vacant$1) {
                return new Tail();
              } else {
                return new Apply$1(
                  new Apply$1(new Cons$1(), target),
                  new Tail(),
                );
              }
            })();
            return [new$, state.mode, toList([])];
          },
        );
      },
    );
  }

  function extend_list(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            let new$ = (() => {
              if (target instanceof Apply$1 &&
              target.func instanceof Apply$1 &&
              target.func.func instanceof Cons$1) {
                return new Apply$1(
                  new Apply$1(new Cons$1(), new Vacant$1("")),
                  target,
                );
              } else if (target instanceof Tail) {
                return new Apply$1(
                  new Apply$1(new Cons$1(), new Vacant$1("")),
                  target,
                );
              } else {
                return target;
              }
            })();
            return [new$, state.mode, toList([])];
          },
        );
      },
    );
  }

  function spread_list(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            let new$ = (() => {
              if (target instanceof Apply$1 &&
              target.func instanceof Apply$1 &&
              target.func.func instanceof Cons$1 &&
              target.argument instanceof Tail) {
                let item = target.func.argument;
                return item;
              } else if (target instanceof Tail) {
                return new Vacant$1("");
              } else {
                return target;
              }
            })();
            return [new$, state.mode, toList([])];
          },
        );
      },
    );
  }

  function call(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Apply$1(target, new Vacant$1("")),
              state.mode,
              toList([1]),
            ];
          },
        );
      },
    );
  }

  function number(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (_) => { return [new Integer$3(0), new Insert(), toList([])]; },
        );
      },
    );
  }

  function match(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (target) => {
            return [
              new Apply$1(
                new Apply$1(new Case(""), new Vacant$1("")),
                target,
              ),
              new Insert(),
              toList([]),
            ];
          },
        );
      },
    );
  }

  function nocases(state, start, end) {
    return single_focus(
      state,
      start,
      end,
      (path) => {
        return update_at(
          state,
          path,
          (_) => { return [new NoCases$1(), state.mode, toList([])]; },
        );
      },
    );
  }

  function insert_text(state, data, start, end) {
    let rendered = state.rendered[0];
    let $ = state.mode;
    if ($ instanceof Command) {
      if (data === " ") {
        let $1 = state.inferred;
        if ($1 instanceof Some) {
          let $2 = run$1(state);
          let message = $2[0];
          let actions = $2[1];
          let state$1 = state.withFields({ mode: new Command(message) });
          return [state$1, start, actions];
        } else if ($1 instanceof None) {
          let inferred = do_infer(state.source, state.env);
          let state$1 = state.withFields({
            mode: new Command(""),
            inferred: new Some(inferred)
          });
          return [state$1, start, toList([])];
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            492,
            "insert_text",
            "No case clause matched",
            { values: [$1] }
          )
        }
      } else if (data === "Q") {
        then(
          showSaveFilePicker(),
          (result) => {
            let $1 = (() => {
              let _pipe = result;
              return debug$2(_pipe);
            })();
            if ($1.isOk()) {
              let file_handle = $1[0];
              return then(
                createWritable(file_handle),
                (writable) => {
                  debug$2(writable);
                  let blob$1 = blob(
                    toArray(toList([to_json(state.source)])),
                    "application/json",
                  );
                  debug$2(blob$1);
                  return then(
                    write(writable, blob$1),
                    (_) => {
                      return then(
                        close(writable),
                        (_) => { return resolve$1(undefined); },
                      );
                    },
                  );
                },
              );
            } else if (!$1.isOk() && !$1[0]) {
              debug$2("no file  to save selected");
              return resolve$1(undefined);
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                511,
                "",
                "No case clause matched",
                { values: [$1] }
              )
            }
          },
        );
        return [state, start, toList([])];
      } else if (data === "q") {
        let dump = to_json(state.source);
        let request = (() => {
          let _pipe = new$$1();
          let _pipe$1 = set_method(_pipe, new Post());
          let _pipe$2 = set_scheme(_pipe$1, new Http());
          let _pipe$3 = set_host(_pipe$2, "localhost:8080");
          let _pipe$4 = set_path(_pipe$3, "/save");
          return set_body(_pipe$4, dump);
        })();
        map_promise(
          send(request),
          (response) => {
            if (response.isOk() &&
            response[0] instanceof Response &&
            response[0].status === 200) {
              return undefined;
            } else {
              debug$2("failed to save");
              return undefined;
            }
          },
        );
        return [state, start, toList([])];
      } else if (data === "w") {
        return call_with(state, start, end);
      } else if (data === "e") {
        return assign_to(state, start, end);
      } else if (data === "E") {
        return assign_before(state, start, end);
      } else if (data === "r") {
        return extend(state, start, end);
      } else if (data === "R") {
        return extender(state, start, end);
      } else if (data === "t") {
        return tag(state, start, end);
      } else if (data === "y") {
        return copy(state, start, end);
      } else if (data === "Y") {
        return paste(state, start, end);
      } else if (data === "i") {
        return [state.withFields({ mode: new Insert() }), start, toList([])];
      } else if (data === "[") {
        return list_element(state, start, end);
      } else if (data === "x") {
        return list_element(state, start, end);
      } else if (data === ",") {
        return extend_list(state, start, end);
      } else if (data === ".") {
        return spread_list(state, start, end);
      } else if (data === "o") {
        return overwrite(state, start, end);
      } else if (data === "p") {
        return perform(state, start, end);
      } else if (data === "s") {
        return string(state, start, end);
      } else if (data === "d") {
        return delete$(state, start, end);
      } else if (data === "f") {
        return insert_function(state, start, end);
      } else if (data === "g") {
        return select(state, start, end);
      } else if (data === "h") {
        return handle(state, start, end);
      } else if (data === "H") {
        return shallow(state, start, end);
      } else if (data === "j") {
        return builtin(state, start, end);
      } else if (data === "z") {
        return undo(state, start);
      } else if (data === "Z") {
        return redo(state, start);
      } else if (data === "c") {
        return call(state, start, end);
      } else if (data === "b") {
        return binary(state, start, end);
      } else if (data === "n") {
        return number(state, start, end);
      } else if (data === "m") {
        return match(state, start, end);
      } else if (data === "M") {
        return nocases(state, start, end);
      } else {
        let key = data;
        let mode = new Command(append$2("no command for key ", key));
        return [state.withFields({ mode: mode }), start, toList([])];
      }
    } else if ($ instanceof Insert) {
      let $1 = at$1(rendered, start);
      if (!$1.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          611,
          "insert_text",
          "Assignment pattern did not match",
          { value: $1 }
        )
      }
      let path = $1[0][1];
      let cut_start = $1[0][2];
      let $2 = at$1(rendered, end);
      if (!$2.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          613,
          "insert_text",
          "Assignment pattern did not match",
          { value: $2 }
        )
      }
      let cut_end = $2[0][2];
      let is_letters = (is_var(data) || is_tag(data)) || is_num(data);
      let $3 = (() => {
        let $4 = (cut_start < 0) && is_letters;
        if ($4) {
          let $5 = at$1(rendered, start - 1);
          if (!$5.isOk()) {
            throw makeError(
              "assignment_no_match",
              "easel/embed",
              617,
              "insert_text",
              "Assignment pattern did not match",
              { value: $5 }
            )
          }
          let path$1 = $5[0][1];
          let cut_start$1 = $5[0][2];
          return [path$1, cut_start$1 + 1];
        } else if (!$4) {
          return [path, cut_start];
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            615,
            "insert_text",
            "No case clause matched",
            { values: [$4] }
          )
        }
      })();
      let path$1 = $3[0];
      let cut_start$1 = $3[1];
      let $4 = (() => {
        let $5 = cut_end < 0;
        if ($5) {
          let $6 = at$1(rendered, end - 1);
          if (!$6.isOk()) {
            throw makeError(
              "assignment_no_match",
              "easel/embed",
              629,
              "insert_text",
              "Assignment pattern did not match",
              { value: $6 }
            )
          }
          let path$2 = $6[0][1];
          let cut_end$1 = $6[0][2];
          return [path$2, cut_end$1 + 1];
        } else if (!$5) {
          return [path$1, cut_end];
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            627,
            "insert_text",
            "No case clause matched",
            { values: [$5] }
          )
        }
      })();
      let p2 = $4[0];
      let cut_end$1 = $4[1];
      let $5 = (!isEqual(path$1, p2)) || (cut_start$1 < 0);
      if ($5) {
        return [state, start, toList([])];
      } else {
        let $6 = at(state.source, path$1);
        if (!$6.isOk()) {
          throw makeError(
            "assignment_no_match",
            "easel/embed",
            641,
            "insert_text",
            "Assignment pattern did not match",
            { value: $6 }
          )
        }
        let target = $6[0][0];
        let rezip = $6[0][1];
        debug$2(target);
        let $7 = (() => {
          if (target instanceof Lambda) {
            let param = target.label;
            let body = target.body;
            let $8 = replace_at(param, cut_start$1, cut_end$1, data);
            let param$1 = $8[0];
            let offset = $8[1];
            return [new Lambda(param$1, body), toList([]), offset, true];
          } else if (target instanceof Apply$1 &&
          target.func instanceof Apply$1 &&
          target.func.func instanceof Cons$1) {
            let new$ = new Apply$1(
              new Apply$1(new Cons$1(), new Vacant$1("")),
              target,
            );
            return [new$, toList([0, 1]), 0, false];
          } else if (target instanceof Apply$1 &&
          target.func instanceof Apply$1 &&
          target.func.func instanceof Extend$2) {
            let label = target.func.func.label;
            let value = target.func.argument;
            let rest = target.argument;
            let $8 = cut_start$1 <= 0;
            if (data === "," && $8) {
              let new$ = new Apply$1(
                new Apply$1(new Extend$2(""), new Vacant$1("")),
                target,
              );
              return [new$, toList([]), 0, true];
            } else {
              let $9 = replace_at(label, cut_start$1, cut_end$1, data);
              let label$1 = $9[0];
              let offset = $9[1];
              return [
                new Apply$1(new Apply$1(new Extend$2(label$1), value), rest),
                toList([]),
                offset,
                true,
              ];
            }
          } else if (target instanceof Apply$1 &&
          target.func instanceof Apply$1 &&
          target.func.func instanceof Overwrite$1) {
            let label = target.func.func.label;
            let value = target.func.argument;
            let rest = target.argument;
            let $8 = cut_start$1 <= 0;
            if (data === "," && $8) {
              let new$ = new Apply$1(
                new Apply$1(new Overwrite$1(""), new Vacant$1("")),
                target,
              );
              return [new$, toList([]), 0, true];
            } else {
              let $9 = replace_at(label, cut_start$1, cut_end$1, data);
              let label$1 = $9[0];
              let offset = $9[1];
              return [
                new Apply$1(new Apply$1(new Overwrite$1(label$1), value), rest),
                toList([]),
                offset,
                true,
              ];
            }
          } else if (target instanceof Let) {
            let label = target.label;
            let value = target.definition;
            let then$ = target.body;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Let(label$1, value, then$), toList([]), offset, true];
          } else if (target instanceof Variable) {
            let label = target.label;
            let $8 = is_var(data) || (is_num(data) && (cut_start$1 > 0));
            if ($8) {
              let $9 = replace_at(label, cut_start$1, cut_end$1, data);
              let label$1 = $9[0];
              let offset = $9[1];
              let $10 = (() => {
                if (label$1 === "") {
                  return [new Vacant$1(""), false];
                } else {
                  return [new Variable(label$1), true];
                }
              })();
              let new$ = $10[0];
              let text_only = $10[1];
              return [new$, toList([]), offset, text_only];
            } else if (!$8) {
              if (data === "{") {
                return [
                  new Apply$1(
                    new Apply$1(new Overwrite$1(""), new Vacant$1("")),
                    target,
                  ),
                  toList([]),
                  0,
                  false,
                ];
              } else {
                return [target, toList([]), cut_start$1, true];
              }
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                695,
                "insert_text",
                "No case clause matched",
                { values: [$8] }
              )
            }
          } else if (target instanceof Vacant$1) {
            if (data === "\"") {
              return [new Str$2(""), toList([]), 0, false];
            } else if (data === "[") {
              return [new Tail(), toList([]), 0, false];
            } else if (data === "{") {
              return [new Empty(), toList([]), 0, false];
            } else if (data === "(") {
              return [
                new Apply$1(new Vacant$1(""), new Vacant$1("")),
                toList([]),
                0,
                false,
              ];
            } else if (data === "=") {
              return [
                new Let("", new Vacant$1(""), new Vacant$1("")),
                toList([]),
                0,
                false,
              ];
            } else if (data === "|") {
              return [
                new Apply$1(
                  new Apply$1(new Case(""), new Vacant$1("")),
                  new Vacant$1(""),
                ),
                toList([]),
                0,
                false,
              ];
            } else if (data === "^") {
              return [new Perform$1(""), toList([]), 0, false];
            } else {
              let $8 = parse$1(data);
              if ($8.isOk()) {
                let number$1 = $8[0];
                return [
                  new Integer$3(number$1),
                  toList([]),
                  length$2(data),
                  false,
                ];
              } else if (!$8.isOk() && !$8[0]) {
                let $9 = is_var(data);
                if ($9) {
                  return [
                    new Variable(data),
                    toList([]),
                    length$2(data),
                    false,
                  ];
                } else if (!$9) {
                  let $10 = is_tag(data);
                  if ($10) {
                    return [
                      new Tag$1(data),
                      toList([]),
                      length$2(data),
                      false,
                    ];
                  } else if (!$10) {
                    return [target, toList([]), cut_start$1, true];
                  } else {
                    throw makeError(
                      "case_no_match",
                      "easel/embed",
                      750,
                      "insert_text",
                      "No case clause matched",
                      { values: [$10] }
                    )
                  }
                } else {
                  throw makeError(
                    "case_no_match",
                    "easel/embed",
                    742,
                    "insert_text",
                    "No case clause matched",
                    { values: [$9] }
                  )
                }
              } else {
                throw makeError(
                  "case_no_match",
                  "easel/embed",
                  734,
                  "insert_text",
                  "No case clause matched",
                  { values: [$8] }
                )
              }
            }
          } else if (target instanceof Str$2) {
            let value = target.value;
            let value$1 = replace_at$1(value, cut_start$1, cut_end$1, data);
            return [
              new Str$2(value$1),
              toList([]),
              cut_start$1 + length$2(data),
              true,
            ];
          } else if (target instanceof Integer$3) {
            let value = target.value;
            let $8 = (data === "-") && (cut_start$1 === 0);
            if ($8) {
              return [new Integer$3(0 - value), toList([]), 1, true];
            } else if (!$8) {
              let $9 = parse$1(data);
              if ($9.isOk()) {
                let $10 = (() => {
                  let _pipe = to_string$7(value);
                  let _pipe$1 = replace_at$1(
                    _pipe,
                    cut_start$1,
                    cut_end$1,
                    data,
                  );
                  return parse$1(_pipe$1);
                })();
                if (!$10.isOk()) {
                  throw makeError(
                    "assignment_no_match",
                    "easel/embed",
                    773,
                    "insert_text",
                    "Assignment pattern did not match",
                    { value: $10 }
                  )
                }
                let value$1 = $10[0];
                return [
                  new Integer$3(value$1),
                  toList([]),
                  cut_start$1 + length$2(data),
                  true,
                ];
              } else if (!$9.isOk() && !$9[0]) {
                return [target, toList([]), cut_start$1, false];
              } else {
                throw makeError(
                  "case_no_match",
                  "easel/embed",
                  771,
                  "insert_text",
                  "No case clause matched",
                  { values: [$9] }
                )
              }
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                768,
                "insert_text",
                "No case clause matched",
                { values: [$8] }
              )
            }
          } else if (target instanceof Tail) {
            if (data === ",") {
              return [
                new Apply$1(
                  new Apply$1(new Cons$1(), new Vacant$1("")),
                  new Vacant$1(""),
                ),
                toList([0, 1]),
                cut_start$1,
                false,
              ];
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                789,
                "insert_text",
                "No case clause matched",
                { values: [data] }
              )
            }
          } else if (target instanceof Empty) {
            if (data === ",") {
              return [
                new Apply$1(
                  new Apply$1(new Extend$2(""), new Vacant$1("")),
                  new Vacant$1(""),
                ),
                toList([0, 1]),
                cut_start$1,
                false,
              ];
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                799,
                "insert_text",
                "No case clause matched",
                { values: [data] }
              )
            }
          } else if (target instanceof Extend$2) {
            let label = target.label;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Extend$2(label$1), toList([]), offset, true];
          } else if (target instanceof Select$1) {
            let label = target.label;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Select$1(label$1), toList([]), offset, true];
          } else if (target instanceof Overwrite$1) {
            let label = target.label;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Overwrite$1(label$1), toList([]), offset, true];
          } else if (target instanceof Tag$1) {
            let label = target.label;
            let $8 = is_tag(data);
            if ($8) {
              let $9 = replace_at(label, cut_start$1, cut_end$1, data);
              let label$1 = $9[0];
              let offset = $9[1];
              return [new Tag$1(label$1), toList([]), offset, true];
            } else if (!$8) {
              return [target, toList([]), cut_start$1, false];
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                821,
                "insert_text",
                "No case clause matched",
                { values: [$8] }
              )
            }
          } else if (target instanceof Apply$1 &&
          target.func instanceof Apply$1 &&
          target.func.func instanceof Case) {
            let label = target.func.func.label;
            let value = target.func.argument;
            let rest = target.argument;
            let $8 = is_tag(data);
            if ($8) {
              let $9 = replace_at(label, cut_start$1, cut_end$1, data);
              let label$1 = $9[0];
              let offset = $9[1];
              return [
                new Apply$1(new Apply$1(new Case(label$1), value), rest),
                toList([]),
                offset,
                true,
              ];
            } else if (!$8) {
              return [target, toList([]), cut_start$1, false];
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                831,
                "insert_text",
                "No case clause matched",
                { values: [$8] }
              )
            }
          } else if (target instanceof Case) {
            let label = target.label;
            let $8 = is_tag(data);
            if ($8) {
              let $9 = replace_at(label, cut_start$1, cut_end$1, data);
              let label$1 = $9[0];
              let offset = $9[1];
              return [new Case(label$1), toList([]), offset, true];
            } else if (!$8) {
              return [target, toList([]), cut_start$1, false];
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                846,
                "insert_text",
                "No case clause matched",
                { values: [$8] }
              )
            }
          } else if (target instanceof Perform$1) {
            let label = target.label;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Perform$1(label$1), toList([]), offset, true];
          } else if (target instanceof Handle$1) {
            let label = target.label;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Handle$1(label$1), toList([]), offset, true];
          } else if (target instanceof Shallow$1) {
            let label = target.label;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Shallow$1(label$1), toList([]), offset, true];
          } else if (target instanceof Builtin$2) {
            let label = target.identifier;
            let $8 = replace_at(label, cut_start$1, cut_end$1, data);
            let label$1 = $8[0];
            let offset = $8[1];
            return [new Builtin$2(label$1), toList([]), offset, true];
          } else {
            let node = target;
            debug$2(["nothing", node]);
            return [node, toList([]), cut_start$1, false];
          }
        })();
        let new$ = $7[0];
        let sub = $7[1];
        let offset = $7[2];
        let text_only = $7[3];
        let $8 = isEqual(target, new$);
        if ($8) {
          return [state, start, toList([])];
        } else if (!$8) {
          let new$1 = rezip(new$);
          let backwards = (() => {
            let $9 = state.history[1];
            if ($9.atLeastLength(1) &&
            $9.head[2] &&
            (isEqual($9.head[1], path$1)) && text_only) {
              let original = $9.head[0];
              $9.head[1];
              let rest = $9.tail;
              return toList([[original, path$1, true]], rest);
            } else {
              return toList([[state.source, path$1, true]], state.history[1]);
            }
          })();
          let history = [toList([]), backwards];
          let inferred = (() => {
            let $9 = state.auto_infer;
            if ($9) {
              return new Some(do_infer(new$1, state.env));
            } else if (!$9) {
              return new None();
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                889,
                "insert_text",
                "No case clause matched",
                { values: [$9] }
              )
            }
          })();
          let rendered$1 = print(
            new$1,
            new Some(path$1),
            state.auto_infer,
            inferred,
          );
          let path$2 = append$3(path$1, sub);
          let $9 = get(rendered$1[1], path_to_string(path$2));
          if (!$9.isOk()) {
            throw makeError(
              "assignment_no_match",
              "easel/embed",
              900,
              "insert_text",
              "Assignment pattern did not match",
              { value: $9 }
            )
          }
          let start$1 = $9[0];
          return [
            state.withFields({
              source: new$1,
              history: history,
              inferred: inferred,
              focus: new Some(path$2),
              rendered: rendered$1
            }),
            start$1 + offset,
            toList([]),
          ];
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            876,
            "insert_text",
            "No case clause matched",
            { values: [$8] }
          )
        }
      }
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        488,
        "insert_text",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function insert_paragraph(index, state) {
    let $ = at$1(state.rendered[0], index);
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        1242,
        "insert_paragraph",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let path = $[0][1];
    let offset = $[0][2];
    let source = state.source;
    let $1 = at(source, path);
    if (!$1.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        1245,
        "insert_paragraph",
        "Assignment pattern did not match",
        { value: $1 }
      )
    }
    let target = $1[0][0];
    let rezip = $1[0][1];
    let $2 = (() => {
      if (target instanceof Str$2) {
        let content = target.value;
        let $3 = replace_at(content, offset, offset, "\n");
        let content$1 = $3[0];
        let offset$1 = $3[1];
        return [new Str$2(content$1), toList([]), offset$1];
      } else if (target instanceof Let) {
        let label = target.label;
        let value = target.definition;
        let then$ = target.body;
        return [
          new Let(label, value, new Let("", new Vacant$1(""), then$)),
          toList([1]),
          0,
        ];
      } else {
        let node = target;
        return [new Let("", node, new Vacant$1("")), toList([1]), 0];
      }
    })();
    let new$ = $2[0];
    let sub = $2[1];
    let offset$1 = $2[2];
    let new$1 = rezip(new$);
    let history = [toList([]), toList([[source, path, false]], state.history[1])];
    let inferred = (() => {
      let $3 = (() => {
        let _pipe = state.auto_infer;
        return debug$2(_pipe);
      })();
      if ($3) {
        return new Some(do_infer(new$1, state.env));
      } else if (!$3) {
        return new None();
      } else {
        throw makeError(
          "case_no_match",
          "easel/embed",
          1261,
          "insert_paragraph",
          "No case clause matched",
          { values: [$3] }
        )
      }
    })();
    let rendered = print(new$1, new Some(path), state.auto_infer, inferred);
    let $3 = get(rendered[1], path_to_string(append$3(path, sub)));
    if (!$3.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        1270,
        "insert_paragraph",
        "Assignment pattern did not match",
        { value: $3 }
      )
    }
    let start = $3[0];
    return [
      state.withFields({
        mode: new Insert(),
        source: new$1,
        history: history,
        inferred: inferred,
        rendered: rendered,
        focus: new Some(path)
      }),
      start + offset$1,
    ];
  }

  function pallet(embed) {
    let $ = embed.mode;
    if ($ instanceof Command) {
      let warning = $.warning;
      let message = (() => {
        if (warning === "") {
          let $1 = embed.inferred;
          let $2 = embed.focus;
          if ($2 instanceof Some) {
            let types = $1;
            let path = $2[0];
            let $3 = type_at(path, types);
            if ($3 instanceof Some && $3[0].isOk()) {
              return "press space to run";
            } else if ($3 instanceof Some && !$3[0].isOk()) {
              let r = $3[0][0][0];
              $3[0][0][1];
              $3[0][0][2];
              return render_failure(r);
            } else if ($3 instanceof None) {
              return "press space to type check";
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                1320,
                "pallet",
                "No case clause matched",
                { values: [$3] }
              )
            }
          } else {
            return "press space to run";
          }
        } else {
          let message = warning;
          return message;
        }
      })();
      return append$2(":", message);
    } else if ($ instanceof Insert) {
      return "insert";
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        1314,
        "pallet",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function escape_html(source) {
    let _pipe = source;
    let _pipe$1 = replace$2(_pipe, "&", "&amp;");
    let _pipe$2 = replace$2(_pipe$1, "<", "&lt;");
    return replace$2(_pipe$2, ">", "&gt;");
  }

  function to_html(sections) {
    return fold$4(
      sections,
      "",
      (acc, section) => {
        let style = section[0];
        let err = section[1];
        let letters = section[2];
        let class$ = (() => {
          if (style instanceof Default) {
            return toList([]);
          } else if (style instanceof Keyword) {
            return toList(["text-gray-500"]);
          } else if (style instanceof Missing) {
            return toList(["text-pink-3"]);
          } else if (style instanceof Hole) {
            return toList(["text-orange-4 font-bold"]);
          } else if (style instanceof Integer$2) {
            return toList(["text-purple-4"]);
          } else if (style instanceof String$1) {
            return toList(["text-green-4"]);
          } else if (style instanceof Label) {
            return toList(["text-blue-3"]);
          } else if (style instanceof Effect$2) {
            return toList(["text-yellow-4"]);
          } else if (style instanceof Builtin$1) {
            return toList(["italic underline"]);
          } else {
            throw makeError(
              "case_no_match",
              "easel/embed",
              1345,
              "",
              "No case clause matched",
              { values: [style] }
            )
          }
        })();
        let class$1 = (() => {
          let _pipe = (() => {
            if (!err) {
              return class$;
            } else if (err) {
              return append$3(class$, toList(["border-b-2 border-orange-4"]));
            } else {
              throw makeError(
                "case_no_match",
                "easel/embed",
                1357,
                "",
                "No case clause matched",
                { values: [err] }
              )
            }
          })();
          return join(_pipe, " ");
        })();
        return concat(
          toList([
            acc,
            "<span class=\"",
            class$1,
            "\">",
            escape_html(concat(letters)),
            "</span>",
          ]),
        );
      },
    );
  }

  function html(embed) {
    let _pipe = embed.rendered[0];
    let _pipe$1 = group(_pipe);
    return to_html(_pipe$1);
  }

  function render_page(root, start, state) {
    let $ = querySelector(root, "pre");
    if ($.isOk()) {
      let pre = $[0];
      setInnerHTML(pre, html(state));
      let pallet_el = nextElementSibling(pre);
      setInnerHTML(pallet_el, pallet(state));
    } else if (!$.isOk() && !$[0]) {
      let content = concat(
        toList([
          "<pre class=\"expand overflow-auto outline-none w-full my-1 mx-4\" contenteditable spellcheck=\"false\">",
          html(state),
          "</pre>",
          "<div class=\"w-full bg-purple-1 px-4 font-mono font-bold\">",
          pallet(state),
          "</div>",
        ]),
      );
      setInnerHTML(root, content);
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        344,
        "render_page",
        "No case clause matched",
        { values: [$] }
      )
    }
    let $1 = querySelector(root, "pre");
    if (!$1.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/embed",
        366,
        "render_page",
        "Assignment pattern did not match",
        { value: $1 }
      )
    }
    let pre = $1[0];
    return placeCursor(pre, start);
  }

  function start_easel_at(root, start, state) {
    render_page(root, start, state);
    let ref = make_reference(state);
    let $ = querySelector(root, "pre");
    if ($.isOk()) {
      let pre = $[0];
      addEventListener(
        pre,
        "blur",
        (_) => {
          debug$2("blurred");
          update_reference(
            ref,
            (state) => {
              let state$1 = blur(state);
              setInnerHTML(pre, html(state$1));
              let pallet_el = nextElementSibling(pre);
              setInnerHTML(pallet_el, pallet(state$1));
              return state$1;
            },
          );
          return undefined;
        },
      );
    } else {
      debug$2("expected a pre to be available");
    }
    addEventListener(
      doc(),
      "selectionchange",
      (_) => {
        then$(
          getSelection(),
          (selection) => {
            return then$(
              getRangeAt(selection),
              (range) => {
                let start$1 = startIndex(range);
                let end = endIndex(range);
                update_reference(
                  ref,
                  (state) => {
                    let state$1 = update_selection(state, start$1, end);
                    let rendered = print(
                      state$1.source,
                      state$1.focus,
                      state$1.auto_infer,
                      state$1.inferred,
                    );
                    let $2 = isEqual(rendered, state$1.rendered);
                    if ($2) {
                      debug$2("no focus change");
                      return state$1;
                    } else if (!$2) {
                      let $3 = get(
                        rendered[1],
                        path_to_string(
                          unwrap(state$1.focus, toList([])),
                        ),
                      );
                      if (!$3.isOk()) {
                        throw makeError(
                          "assignment_no_match",
                          "easel/embed",
                          221,
                          "",
                          "Assignment pattern did not match",
                          { value: $3 }
                        )
                      }
                      let start$2 = $3[0];
                      let state$2 = state$1.withFields({ rendered: rendered });
                      render_page(root, start$2, state$2);
                      return state$2;
                    } else {
                      throw makeError(
                        "case_no_match",
                        "easel/embed",
                        215,
                        "",
                        "No case clause matched",
                        { values: [$2] }
                      )
                    }
                  },
                );
                return new Ok$1(undefined);
              },
            );
          },
        );
        
        return undefined;
      },
    );
    addEventListener(
      root,
      "beforeinput",
      (event) => {
        preventDefault(event);
        return handleInput$1(
          event,
          (data, start, end) => {
            update_reference(
              ref,
              (state) => {
                let $1 = insert_text(state, data, start, end);
                let state$1 = $1[0];
                let start$1 = $1[1];
                let actions = $1[2];
                render_page(root, start$1, state$1);
                debug$2(actions);
                map$1(
                  actions,
                  (updater) => {
                    return map_promise(
                      updater,
                      (updater) => {
                        return update_reference(
                          ref,
                          (state) => {
                            let state$1 = updater(state);
                            debug$2("lots of update");
                            render_page(root, start$1, state$1);
                            return state$1;
                          },
                        );
                      },
                    );
                  },
                );
                return state$1;
              },
            );
            return undefined;
          },
          (start) => {
            update_reference(
              ref,
              (state) => {
                let $1 = insert_paragraph(start, state);
                let state$1 = $1[0];
                let start$1 = $1[1];
                render_page(root, start$1, state$1);
                return state$1;
              },
            );
            debug$2([start]);
            return undefined;
          },
        );
      },
    );
    return addEventListener(
      root,
      "keydown",
      (event) => {
        let $1 = (() => {
          let $2 = eventKey(event);
          if ($2 === "Escape") {
            update_reference(
              ref,
              (s) => {
                let s$1 = escape(s);
                let $3 = querySelector(root, "pre + *");
                if ($3.isOk()) {
                  let pallet_el = $3[0];
                  setInnerHTML(pallet_el, pallet(s$1));
                } else if (!$3.isOk() && !$3[0]) ; else {
                  throw makeError(
                    "case_no_match",
                    "easel/embed",
                    308,
                    "",
                    "No case clause matched",
                    { values: [$3] }
                  )
                }
                return s$1;
              },
            );
            return new Ok$1(undefined);
          } else {
            return new Error$1(undefined);
          }
        })();
        if ($1.isOk() && !$1[0]) {
          return preventDefault(event);
        } else if (!$1.isOk() && !$1[0]) {
          return undefined;
        } else {
          throw makeError(
            "case_no_match",
            "easel/embed",
            301,
            "",
            "No case clause matched",
            { values: [$1] }
          )
        }
      },
    );
  }

  function handle_click(root, event) {
    let $ = nearest_click_handler$1(event);
    if ($.isOk() && $[0] === "load") {
      map_try(
        load_source(),
        (source) => {
          let env$1 = env();
          let sub = new$$2();
          let next = 0;
          let tenv = new$$2();
          let cache = [env$1, sub, next, tenv];
          let inferred = new Some(
            infer_env(
              source,
              new Var(-3),
              new Var(-4),
              tenv,
              sub,
              next,
            )[0],
          );
          let rendered = print(
            source,
            new Some(toList([])),
            false,
            inferred,
          );
          let $1 = get(rendered[1], path_to_string(toList([])));
          if (!$1.isOk()) {
            throw makeError(
              "assignment_no_match",
              "easel/embed",
              132,
              "",
              "Assignment pattern did not match",
              { value: $1 }
            )
          }
          let start = $1[0];
          let state = new Embed(
            new Command(""),
            new None(),
            cache,
            source,
            [toList([]), toList([])],
            false,
            inferred,
            new None(),
            rendered,
            new None(),
          );
          start_easel_at(root, start, state);
          return new Ok$1(undefined);
        },
      );
      return undefined;
    } else if ($.isOk()) {
      debug$2(["unknown click", handle]);
      return undefined;
    } else if (!$.isOk() && !$[0]) {
      return undefined;
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        111,
        "handle_click",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function fullscreen(root) {
    addEventListener(
      root,
      "click",
      (_capture) => { return handle_click(root, _capture); },
    );
    setInnerHTML(
      root,
      "<div  class=\"cover expand vstack pointer\"><div class=\"cover text-center cursor-pointer\" data-click=\"load\">click to load</div><div class=\"cover text-center cursor-pointer hidden\" data-click=\"new\">start new</div></div>",
    );
    return undefined;
  }

  function snippet(root) {
    debug$2("start snippet");
    let $ = querySelector(root, "script[type=\"application/eygir\"]");
    if ($.isOk()) {
      let script = $[0];
      let $1 = from_json(innerText(script));
      if (!$1.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          387,
          "snippet",
          "Assignment pattern did not match",
          { value: $1 }
        )
      }
      let source = $1[0];
      let $2 = infer(source, new Var(-1), new Var(-2));
      let sub = $2[0][0];
      let next = $2[0][1];
      let envs = $2[1];
      let $3 = resumable(source, env(), new None());
      if (!($3[0] instanceof Value) || !($3[0].term instanceof Function$1)) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          392,
          "snippet",
          "Assignment pattern did not match",
          { value: $3 }
        )
      }
      let source$1 = $3[0].term.body;
      let rev = $3[0].term.path;
      let env$1 = $3[1];
      let $4 = get(envs, rev);
      if (!$4.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          394,
          "snippet",
          "Assignment pattern did not match",
          { value: $4 }
        )
      }
      let tenv = $4[0];
      let inferred = new Some(
        infer_env(source$1, new Var(-3), new Var(-4), tenv, sub, next)[0],
      );
      let rendered = print(source$1, new Some(toList([])), false, inferred);
      let $5 = get(rendered[1], path_to_string(toList([])));
      if (!$5.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/embed",
          399,
          "snippet",
          "Assignment pattern did not match",
          { value: $5 }
        )
      }
      let start = $5[0];
      let state = new Embed(
        new Command(""),
        new None(),
        [env$1, sub, next, tenv],
        source$1,
        [toList([]), toList([])],
        true,
        inferred,
        new None(),
        rendered,
        new None(),
      );
      setInnerHTML(root, "");
      start_easel_at(root, start, state);
      return undefined;
    } else if (!$.isOk() && !$[0]) {
      debug$2("nothing found");
      return undefined;
    } else {
      throw makeError(
        "case_no_match",
        "easel/embed",
        385,
        "snippet",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function nearest_click_handler(event) {
    let target$1 = target(event);
    let $ = closest(target$1, "[data-click]");
    if ($.isOk()) {
      let element = $[0];
      let $1 = datasetGet(element, "click");
      if (!$1.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/loader",
          136,
          "nearest_click_handler",
          "Assignment pattern did not match",
          { value: $1 }
        )
      }
      let handle = $1[0];
      let $2 = parse$1(handle);
      if ($2.isOk()) {
        let id = $2[0];
        return new Ok$1(id);
      } else if (!$2.isOk() && !$2[0]) {
        debug$2(["not an id", handle]);
        return new Error$1(undefined);
      } else {
        throw makeError(
          "case_no_match",
          "easel/loader",
          137,
          "nearest_click_handler",
          "No case clause matched",
          { values: [$2] }
        )
      }
    } else if (!$.isOk() && !$[0]) {
      return new Error$1(undefined);
    } else {
      throw makeError(
        "case_no_match",
        "easel/loader",
        133,
        "nearest_click_handler",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function console_log() {
    return [
      new String$2(),
      unit$3,
      (message, k) => {
        let env = empty();
        let rev = toList([]);
        return require(
          string$1(message),
          rev,
          env,
          k,
          (message) => {
            log(message);
            return prim(new Value(unit$1), rev, env, k);
          },
        );
      },
    ];
  }

  function applet(root) {
    let $ = querySelector(root, "script[type=\"application/eygir\"]");
    if ($.isOk()) {
      let script = $[0];
      log(script);
      let $1 = from_json(
        replace$2(innerText(script), "\\/", "/"),
      );
      if (!$1.isOk()) {
        throw makeError(
          "assignment_no_match",
          "easel/loader",
          44,
          "applet",
          "Assignment pattern did not match",
          { value: $1 }
        )
      }
      let source = $1[0];
      (() => {
        let env$1 = env();
        let rev = toList([]);
        let k = new None();
        let $2 = eval$$1(source, env$1, k);
        if (!($2 instanceof Value)) {
          throw makeError(
            "assignment_no_match",
            "easel/loader",
            50,
            "applet",
            "Assignment pattern did not match",
            { value: $2 }
          )
        }
        let term = $2.term;
        return require(
          field("func", any, term),
          rev,
          env$1,
          k,
          (func) => {
            return require(
              field("arg", any, term),
              rev,
              env$1,
              k,
              (arg) => {
                let actions = make_reference(toList([]));
                let handlers = (() => {
                  let _pipe = new$$2();
                  let _pipe$1 = insert$1(
                    _pipe,
                    "Update",
                    (action, k) => {
                      let saved = dereference(actions);
                      let id = to_string$7(length$3(saved));
                      let saved$1 = toList([action], saved);
                      set_reference(actions, saved$1);
                      return prim(new Value(new Str$1(id)), rev, env$1, k);
                    },
                  );
                  return insert$1(_pipe$1, "Log", console_log()[2]);
                })();
                let state = make_reference(arg);
                let render = () => {
                  let current = dereference(state);
                  let result = handle$1(
                    eval_call(func, current, env$1, new None()),
                    handlers,
                  );
                  let $3 = (() => {
                    if (result instanceof Value &&
                    result.term instanceof Str$1) {
                      let page = result.term.value;
                      return setInnerHTML(root, page);
                    } else {
                      debug$2(["unexpected", result]);
                      return (() => {
                        throw makeError(
                          "todo",
                          "easel/loader",
                          83,
                          "",
                          "panic expression evaluated",
                          {}
                        )
                      })()("nope");
                    }
                  })();
                  
                  return $3;
                };
                addEventListener(
                  root,
                  "click",
                  (event) => {
                    let $3 = nearest_click_handler(event);
                    if ($3.isOk()) {
                      let id = $3[0];
                      let $4 = at$1(
                        reverse(dereference(actions)),
                        id,
                      );
                      if ($4.isOk()) {
                        let code = $4[0];
                        let current = dereference(state);
                        let $5 = eval_call(code, current, env$1, new None());
                        if (!($5 instanceof Value)) {
                          throw makeError(
                            "assignment_no_match",
                            "easel/loader",
                            101,
                            "",
                            "Assignment pattern did not match",
                            { value: $5 }
                          )
                        }
                        let next = $5.term;
                        set_reference(state, next);
                        set_reference(actions, toList([]));
                        render();
                      } else if (!$4.isOk() && !$4[0]) {
                        debug$2("should have been ref");
                      } else {
                        throw makeError(
                          "case_no_match",
                          "easel/loader",
                          94,
                          "",
                          "No case clause matched",
                          { values: [$4] }
                        )
                      }
                      return undefined;
                    } else if (!$3.isOk() && !$3[0]) {
                      return undefined;
                    } else {
                      throw makeError(
                        "case_no_match",
                        "easel/loader",
                        92,
                        "",
                        "No case clause matched",
                        { values: [$3] }
                      )
                    }
                  },
                );
                render();
                return prim(new Value(func), rev, env$1, k);
              },
            );
          },
        );
      })();
      return undefined;
    } else if (!$.isOk() && !$[0]) {
      debug$2("no applet code");
      return undefined;
    } else {
      throw makeError(
        "case_no_match",
        "easel/loader",
        41,
        "applet",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function start$1(container) {
    let $ = datasetGet(container, "ready");
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "easel/loader",
        28,
        "start",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let program = $[0];
    if (program === "editor") {
      return fullscreen(container);
    } else if (program === "snippet") {
      return snippet(container);
    } else if (program === "applet") {
      return applet(container);
    } else {
      debug$2(["unknown program", program]);
      return undefined;
    }
  }

  function run() {
    let containers = querySelectorAll("[data-ready]");
    return map(containers, start$1);
  }

  // Main atelier uses rollup from bundle file to bundle file

  console.log("starting easel");
  function handleInput(event, state) {
    return (
      handleInput$1(
        event,
        function (data, start, end) {
          return insert_text(state, data, start, end);
        },
        function (start) {
          insert_paragraph(start, state);
        }
      ) || state
    );
  }

  // grid of positions from print is not need instead I need to lookup which element has nearest data id and offset
  // need my info page for starting position of each element

  // exactly the same printing logic OR not using embed for new lines
  // if alway looking up before and after

  async function resume(element) {
    // not really a hash at this point just some key
    const hash = element.dataset.easel.slice(1);
    let response = await fetch("/db/" + hash + ".json");
    let json = await response.json();
    let state = init(json);
    let offset = 0;
    element.onclick = function () {
      element.onbeforeinput = function (event) {
        event.preventDefault();
        [state, offset] = handleInput(event, state);
        updateElement(element, state, offset);
        return false;
      };
      element.onkeydown = function (event) {
        if (event.key == "Escape") {
          state = escape(state);
          const selection = window.getSelection();
          const range = selection.getRangeAt(0);
          const start = startIndex(range);
          updateElement(element, state, start);
        }
        if (event.ctrlKey && event.key == "f") {
          event.preventDefault();
          const selection = window.getSelection();
          const range = selection.getRangeAt(0);
          const start = startIndex(range);
          const end = endIndex(range);
          [state, offset] = insert_function(state, start, end);
          updateElement(element, state, offset);
          return false;
        }
        if (event.ctrlKey && event.key == "j") {
          event.preventDefault();
          event.stopPropagation();
          const selection = window.getSelection();
          const range = selection.getRangeAt(0);
          const start = startIndex(range);
          const end = endIndex(range);
          [state, offset] = call_with(state, start, end);
          updateElement(element, state, offset);
          return false;
        }
        console.log(event);
      };
      element.onblur = function (event) {
        // element.nextElementSibling.classList.add("hidden");
        state = blur(state);
        updateElement(element, state);
      };
      element.onfocus = function (event) {
        // element.nextElementSibling.classList.remove("hidden");
      };
      element.onclick = undefined;
      // Separate editor i.e. panel from pallet in ide/workshop
      element.nextElementSibling.innerHTML = pallet(state);
    };
    // maybe on focus should trigger setup
    // maybe embed state should always be rehydrated but the click to edit is a part of that state
    element.innerHTML = html(state);
    element.contentEditable = true;
    return function (range) {
      const start = startIndex(range);
      const end = endIndex(range);
      // console.log("handle selection change", start, end);
      state = update_selection(state, start, end);
      element.nextElementSibling.innerHTML = pallet(state);
    };
  }

  function updateElement(element, state, offset) {
    element.innerHTML = html(state);
    element.nextElementSibling.innerHTML = pallet(state);
    if (offset == undefined) {
      return;
    }
    placeCursor(element, offset);
  }

  async function start() {
    // doesn't work for type module
    // can have a #hash to run or a data-entry for an if statement
    // console.log(document.currentScript);
    // https://gomakethings.com/converting-a-nodelist-to-an-array-with-vanilla-javascript/
    const elements = Array.prototype.slice.call(
      document.querySelectorAll("pre[data-easel]")
    );
    const states = await Promise.all(elements.map(resume));
    // https://javascript.info/selection-range#selection-events
    // only on document level
    document.onselectionchange = function (event) {
      const selection = window.getSelection();
      const range = selection.getRangeAt(0);
      const container = range.startContainer;
      const element = (
        container.closest ? container : container.parentElement
      ).closest("pre[data-easel]");
      // adding after the fact i.e. in response to a load button gets them out of order
      //
      // console.log(element, );
      const index = elements.indexOf(element);
      if (index < 0) {
        if (window.globalSelectionHandler) {
          window.globalSelectionHandler(range);
        }
        return;
      }
      states[index](range);
    };
  }

  start();

  // -------------------------
  // file write
  // const writableStream = await fileHandle.createWritable();
  // const data = new Blob([JSON.stringify({ foo: 2 }, null, 2)], {
  //   type: "application/json",
  // });
  // await writableStream.write(data);
  // --------------

  //     let state = Easel.init(json);
  //     let offset = 0;
  //     // button is the button

  //     pre.onkeydown = function (event) {
  //       if (event.key == "Escape") {
  //         state = Easel.escape(state);
  //         const selection = window.getSelection();
  //         const range = selection.getRangeAt(0);
  //         const start = ffi.startIndex(range);
  //         updateElement(pre, state, start);
  //       }
  //     };
  //   };
  // }

  run();

})();
