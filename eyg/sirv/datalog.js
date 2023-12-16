(function () {
  'use strict';

  class CustomType {
    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
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
      return `[${this.toArray().map(inspect).join(", ")}]`;
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

  function makeError(variant, module, line, fn, message, extra) {
    let error = new globalThis.Error(message);
    error.gleam_error = variant;
    error.module = module;
    error.line = line;
    error.fn = fn;
    for (let k in extra) error[k] = extra[k];
    return error;
  }

  function identity(x) {
    return x;
  }

  function to_string$1(term) {
    return term.toString();
  }

  function to_string(x) {
    return to_string$1(x);
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

  function flatten(lists) {
    return do_concat(lists, toList([]));
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
        loop$acc = toList([x, separator], acc);
      } else {
        throw makeError(
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
      return do_intersperse(rest$1, elem, toList([x]));
    } else {
      throw makeError(
        "case_no_match",
        "gleam/list",
        1119,
        "intersperse",
        "No case clause matched",
        { values: [list] }
      )
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

  function from(a) {
    return identity(a);
  }

  class Effect extends CustomType {
    constructor(all) {
      super();
      this.all = all;
    }
  }

  function none() {
    return new Effect(toList([]));
  }

  function morph(prev, curr, dispatch, parent) {
    if (curr[3]) {
      return prev?.nodeType === 1 &&
        prev.nodeName === curr[0].toUpperCase() &&
        prev.namespaceURI === curr[3]
        ? morphElement(prev, curr, curr[3], dispatch, parent)
        : createElement(prev, curr, curr[3], dispatch, parent);
    }

    if (curr[2]) {
      return prev?.nodeType === 1 && prev.nodeName === curr[0].toUpperCase()
        ? morphElement(prev, curr, null, dispatch, parent)
        : createElement(prev, curr, null, dispatch, parent);
    }

    if (typeof curr?.[0] === "string") {
      return prev?.nodeType === 3
        ? morphText(prev, curr)
        : createText(prev, curr);
    }

    return document.createComment(
      [
        "[internal lustre error] I couldn't work out how to render this element. This",
        "function should only be called internally by lustre's runtime: if you think",
        "this is an error, please open an issue at",
        "https://github.com/hayleigh-dot-dev/gleam-lustre/issues/new",
      ].join(" ")
    );
  }

  // ELEMENTS --------------------------------------------------------------------

  function createElement(prev, curr, ns, dispatch, parent = null) {
    const el = ns
      ? document.createElementNS(ns, curr[0])
      : document.createElement(curr[0]);

    el.$lustre = {};

    let attr = curr[1];
    let dangerousUnescapedHtml = "";

    while (attr.head) {
      if (attr.head[0] === "class") {
        morphAttr(el, attr.head[0], `${el.className} ${attr.head[1]}`);
      } else if (attr.head[0] === "style") {
        morphAttr(el, attr.head[0], `${el.style.cssText} ${attr.head[1]}`);
      } else if (attr.head[0] === "dangerous-unescaped-html") {
        dangerousUnescapedHtml += attr.head[1];
      } else {
        morphAttr(el, attr.head[0], attr.head[1], dispatch);
      }

      attr = attr.tail;
    }

    if (customElements.get(curr[0])) {
      el._slot = curr[2];
    } else if (curr[0] === "slot") {
      let child = new Empty();
      let parentWithSlot = parent;

      while (parentWithSlot) {
        if (parentWithSlot._slot) {
          child = parentWithSlot._slot;
          break;
        } else {
          parentWithSlot = parentWithSlot.parentNode;
        }
      }

      while (child.head) {
        el.appendChild(morph(null, child.head, dispatch, el));
        child = child.tail;
      }
    } else if (dangerousUnescapedHtml) {
      el.innerHTML = dangerousUnescapedHtml;
    } else {
      let child = curr[2];
      while (child.head) {
        el.appendChild(morph(null, child.head, dispatch, el));
        child = child.tail;
      }
    }

    if (prev) prev.replaceWith(el);

    return el;
  }

  function morphElement(prev, curr, ns, dispatch, parent) {
    const prevAttrs = prev.attributes;
    const currAttrs = new Map();

    // This can happen if we're morphing an existing DOM element that *wasn't*
    // initially created by lustre.
    prev.$lustre ??= {};

    let currAttr = curr[1];
    while (currAttr.head) {
      if (currAttr.head[0] === "class" && currAttrs.has("class")) {
        currAttrs.set(
          currAttr.head[0],
          `${currAttrs.get("class")} ${currAttr.head[1]}`
        );
      } else if (currAttr.head[0] === "style" && currAttrs.has("style")) {
        currAttrs.set(
          currAttr.head[0],
          `${currAttrs.get("style")} ${currAttr.head[1]}`
        );
      } else if (
        currAttr.head[0] === "dangerous-unescaped-html" &&
        currAttrs.has("dangerous-unescaped-html")
      ) {
        currAttrs.set(
          currAttr.head[0],
          `${currAttrs.get("dangerous-unescaped-html")} ${currAttr.head[1]}`
        );
      } else {
        currAttrs.set(currAttr.head[0], currAttr.head[1]);
      }

      currAttr = currAttr.tail;
    }

    for (const { name, value: prevValue } of prevAttrs) {
      if (!currAttrs.has(name)) {
        prev.removeAttribute(name);
      } else {
        const value = currAttrs.get(name);

        if (value !== prevValue) {
          morphAttr(prev, name, value, dispatch);
          currAttrs.delete(name);
        }
      }
    }

    for (const [name, value] of currAttrs) {
      morphAttr(prev, name, value, dispatch);
    }

    if (customElements.get(curr[0])) {
      prev._slot = curr[2];
    } else if (curr[0] === "slot") {
      let prevChild = prev.firstChild;
      let currChild = new Empty();
      let parentWithSlot = parent;

      while (parentWithSlot) {
        if (parentWithSlot._slot) {
          currChild = parentWithSlot._slot;
          break;
        } else {
          parentWithSlot = parentWithSlot.parentNode;
        }
      }

      while (prevChild) {
        if (currChild.head) {
          morph(prevChild, currChild.head, dispatch, prev);
          currChild = currChild.tail;
        }

        prevChild = prevChild.nextSibling;
      }

      while (currChild.head) {
        prev.appendChild(morph(null, currChild.head, dispatch, prev));
        currChild = currChild.tail;
      }
    } else if (currAttrs.has("dangerous-unescaped-html")) {
      prev.innerHTML = currAttrs.get("dangerous-unescaped-html");
    } else {
      let prevChild = prev.firstChild;
      let currChild = curr[2];

      while (prevChild) {
        if (currChild.head) {
          const next = prevChild.nextSibling;
          morph(prevChild, currChild.head, dispatch, prev);
          currChild = currChild.tail;
          prevChild = next;
        } else {
          const next = prevChild.nextSibling;
          prevChild.remove();
          prevChild = next;
        }
      }

      while (currChild.head) {
        prev.appendChild(morph(null, currChild.head, dispatch, prev));
        currChild = currChild.tail;
      }
    }

    return prev;
  }

  // ATTRIBUTES ------------------------------------------------------------------

  function morphAttr(el, name, value, dispatch) {
    switch (typeof value) {
      case "string":
        if (el.getAttribute(name) !== value) el.setAttribute(name, value);
        if (value === "") el.removeAttribute(name);
        if (name === "value" && el.value !== value) el.value = value;
        break;

      // Event listeners need to be handled slightly differently because we need
      // to be able to support custom events. We
      case name.startsWith("on") && "function": {
        if (el.$lustre[name] === value) break;

        const event = name.slice(2).toLowerCase();
        const handler = (e) => map(value(e), dispatch);

        if (el.$lustre[`${name}Handler`]) {
          el.removeEventListener(event, el.$lustre[`${name}Handler`]);
        }

        el.addEventListener(event, handler);

        el.$lustre[name] = value;
        el.$lustre[`${name}Handler`] = handler;

        break;
      }

      default:
        el[name] = value;
    }
  }

  // TEXT ------------------------------------------------------------------------

  function createText(prev, curr) {
    const el = document.createTextNode(curr[0]);

    if (prev) prev.replaceWith(el);
    return el;
  }

  function morphText(prev, curr) {
    const prevValue = prev.nodeValue;
    const currValue = curr[0];

    if (!currValue) {
      prev?.remove();
      return null;
    }

    if (prevValue !== currValue) prev.nodeValue = currValue;

    return prev;
  }

  // RUNTIME ---------------------------------------------------------------------

  ///
  ///
  class App {
    #root = null;
    #state = null;
    #queue = [];
    #effects = [];
    #didUpdate = false;

    #init = null;
    #update = null;
    #view = null;

    constructor(init, update, render) {
      this.#init = init;
      this.#update = update;
      this.#view = render;
    }

    start(selector, flags) {
      if (!is_browser()) return new Error(new NotABrowser());
      if (this.#root) return new Error(new AppAlreadyStarted());

      this.#root =
        selector instanceof HTMLElement
          ? selector
          : document.querySelector(selector);

      if (!this.#root) return new Error(new ElementNotFound());

      const [next, effects] = this.#init(flags);

      this.#state = next;
      this.#effects = effects.all.toArray();
      this.#didUpdate = true;

      window.requestAnimationFrame(() => this.#tick());

      return new Ok((msg) => this.dispatch(msg));
    }

    dispatch(msg) {
      this.#queue.push(msg);
      this.#tick();
    }

    emit(name, event = null) {
      this.#root.dispatchEvent(
        new CustomEvent(name, {
          bubbles: true,
          detail: event,
          composed: true,
        })
      );
    }

    destroy() {
      if (!this.#root) return new Error(new AppNotYetStarted());

      this.#root.remove();
      this.#root = null;
      this.#state = null;
      this.#queue = [];
      this.#effects = [];
      this.#didUpdate = false;
      this.#update = () => {};
      this.#view = () => {};
    }

    #tick() {
      this.#flush();

      if (this.#didUpdate) {
        const vdom = this.#view(this.#state);

        this.#root = morph(this.#root, vdom, (msg) => this.dispatch(msg));
        this.#didUpdate = false;
      }
    }

    #flush(times = 0) {
      if (!this.#root) return;
      if (this.#queue.length) {
        while (this.#queue.length) {
          const [next, effects] = this.#update(this.#state, this.#queue.shift());
          // If the user returned their model unchanged and not reconstructed then
          // we don't need to trigger a re-render.
          this.#didUpdate ||= this.#state !== next;
          this.#state = next;
          this.#effects = this.#effects.concat(effects.all.toArray());
        }
      }

      // Each update can produce effects which must now be executed.
      while (this.#effects.length)
        this.#effects.shift()(
          (msg) => this.dispatch(msg),
          (name, data) => this.emit(name, data)
        );

      // Synchronous effects will immediately queue a message to be processed. If
      // it is reasonable, we can process those updates too before proceeding to
      // the next render.
      if (this.#queue.length) {
        times >= 5 ? console.warn(tooManyUpdates) : this.#flush(++times);
      }
    }
  }

  const setup = (init, update, render) => new App(init, update, render);
  const start = (app, selector, flags) => app.start(selector, flags);

  // UTLS ------------------------------------------------------------------------

  const is_browser = () => window && window.document;

  class Attribute extends CustomType {
    constructor(x0, x1, as_property) {
      super();
      this[0] = x0;
      this[1] = x1;
      this.as_property = as_property;
    }
  }

  function attribute(name, value) {
    return new Attribute(name, from(value), false);
  }

  function class$(name) {
    return attribute("class", name);
  }

  class Text extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Element extends CustomType {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  function element(tag, attrs, children) {
    return new Element(tag, attrs, children);
  }

  function text(content) {
    return new Text(content);
  }

  class AppAlreadyStarted extends CustomType {}

  class AppNotYetStarted extends CustomType {}

  class ElementNotFound extends CustomType {}

  class NotABrowser extends CustomType {}

  function simple(init, update, view) {
    let init$1 = (flags) => { return [init(flags), none()]; };
    let update$1 = (model, msg) => { return [update(model, msg), none()]; };
    return setup(init$1, update$1, view);
  }

  class Constraint extends CustomType {
    constructor(head, body) {
      super();
      this.head = head;
      this.body = body;
    }
  }

  class Atom extends CustomType {
    constructor(relation, terms) {
      super();
      this.relation = relation;
      this.terms = terms;
    }
  }

  class Literal extends CustomType {
    constructor(value) {
      super();
      this.value = value;
    }
  }

  class Variable extends CustomType {
    constructor(label) {
      super();
      this.label = label;
    }
  }

  class B extends CustomType {
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

  class I extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function fact$1(relation, values) {
    let terms = map$1(values, (v) => { return v; });
    return new Constraint(new Atom(relation, terms), toList([]));
  }

  function rule$1(relation, terms, body) {
    return new Constraint(new Atom(relation, terms), body);
  }

  function v(label) {
    return new Variable(label);
  }

  function i(value) {
    return new Literal(new I(value));
  }

  function y(relation, terms) {
    return [false, new Atom(relation, terms)];
  }

  function n(relation, terms) {
    return [true, new Atom(relation, terms)];
  }

  class Model extends CustomType {
    constructor(sections) {
      super();
      this.sections = sections;
    }
  }

  class Query extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Paragraph extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function initial() {
    return new Model(
      toList([
        new Paragraph(
          "f the top-level goal clause is read as the denial of the problem, then the empty clause represents false and the proof of the empty clause is a refutation of the denial of the problem. If the top-level goal clause is read as the problem itself, then the empty clause represents true, and the proof of the empty clause is a proof that the problem has a solution.\nThe solution of the problem is a substitution of terms for the variables X in the top-level goal clause, which can be extracted from the resolution proof. Used in this way, goal clauses are similar to conjunctive queries in relational databases, and Horn clause logic is equivalent in computational power to a universal Turing machine.\nVan Emden and Kowalski (1976) investigated the model-theoretic properties of Horn clauses in the context of logic programming, showing that every set of definite clauses D has a unique minimal model M. An atomic formula A is logically implied by D if and only if A is true in M. It follows that a problem P represented by an existentially quantified conjunction of positive literals is logically implied by D if and only if P is true in M. The minimal model semantics of Horn clauses is the basis for the stable model semantics of logic programs.[8] ",
        ),
        new Query(
          toList([
            fact$1("Edge", toList([i(1), i(2)])),
            fact$1("Edge", toList([i(7), i(3)])),
          ]),
        ),
        new Paragraph(
          "lorem simsadf asjdf a.fiuwjfiowqej  vs.df.asdf.aweifqjhwoefj sf  sdf ds f sdf sd f sdf\n  aefdsdfj;fi waepfjlla   a f af awefqafoh;dlfdsf",
        ),
        (() => {
          let x1 = v("x");
          let x2 = v("y");
          let x3 = v("z");
          return new Query(
            toList([
              rule$1(
                "Path",
                toList([x1]),
                toList([y("Edge", toList([x1, x2])), y("Path", toList([x2, x3]))]),
              ),
            ]),
          );
        })(),
        (() => {
          let x1 = v("x");
          return new Query(
            toList([
              rule$1(
                "Foo",
                toList([x1]),
                toList([
                  y("Edge", toList([x1, i(2)])),
                  n("Path", toList([x1, x1])),
                ]),
              ),
            ]),
          );
        })(),
      ]),
    );
  }

  function div(attrs, children) {
    return element("div", attrs, children);
  }

  function p(attrs, children) {
    return element("p", attrs, children);
  }

  function br(attrs) {
    return element("br", attrs, toList([]));
  }

  function span(attrs, children) {
    return element("span", attrs, children);
  }

  function literal(value) {
    if (value instanceof B && value[0]) {
      return text("true");
    } else if (value instanceof B && !value[0]) {
      return text("false");
    } else if (value instanceof I) {
      let i = value[0];
      return text(to_string(i));
    } else if (value instanceof S) {
      value[0];
      return text("some string");
    } else {
      throw makeError(
        "case_no_match",
        "datalog/browser/view/query",
        78,
        "literal",
        "No case clause matched",
        { values: [value] }
      )
    }
  }

  function terms(ts) {
    let _pipe = map$1(
      ts,
      (t) => {
        if (t instanceof Variable) {
          let var$ = t.label;
          return text(var$);
        } else if (t instanceof Literal) {
          let value = t.value;
          return literal(value);
        } else {
          throw makeError(
            "case_no_match",
            "datalog/browser/view/query",
            69,
            "",
            "No case clause matched",
            { values: [t] }
          )
        }
      },
    );
    return intersperse(_pipe, text(", "));
  }

  function atom(a) {
    if (!(a instanceof Atom)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/query",
        54,
        "atom",
        "Assignment pattern did not match",
        { value: a }
      )
    }
    let relation = a.relation;
    let ts = a.terms;
    return span(
      toList([]),
      flatten(
        toList([
          toList([
            span(toList([class$("text-blue-500")]), toList([text(relation)])),
            text("("),
          ]),
          terms(ts),
          toList([text(")")]),
        ]),
      ),
    );
  }

  function fact(a) {
    return span(toList([]), toList([atom(a), text("."), br(toList([]))]));
  }

  function body_atom(b) {
    let negated = b[0];
    let a = b[1];
    if (negated) {
      return span(
        toList([]),
        toList([
          span(
            toList([class$("text-blue-500 font-bold")]),
            toList([text("not ")]),
          ),
          atom(a),
        ]),
      );
    } else if (!negated) {
      return atom(a);
    } else {
      throw makeError(
        "case_no_match",
        "datalog/browser/view/query",
        43,
        "body_atom",
        "No case clause matched",
        { values: [negated] }
      )
    }
  }

  function rule(head, body) {
    return span(
      toList([]),
      flatten(
        toList([
          toList([atom(head), text(" :- ")]),
          (() => {
            let _pipe = map$1(body, body_atom);
            return intersperse(
              _pipe,
              span(toList([class$("outline")]), toList([text(", ")])),
            );
          })(),
          toList([br(toList([]))]),
        ]),
      ),
    );
  }

  function constraint(index, c) {
    if (!(c instanceof Constraint)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/query",
        18,
        "constraint",
        "Assignment pattern did not match",
        { value: c }
      )
    }
    let head = c.head;
    let body = c.body;
    if (body.hasLength(0)) {
      return fact(head);
    } else {
      return rule(head, body);
    }
  }

  function render$1(i, constraints) {
    let constraints$1 = index_map(constraints, constraint);
    return div(
      toList([class$("cover")]),
      toList(
        [span(toList([]), toList([text(to_string(i))])), br(toList([]))],
        constraints$1,
      ),
    );
  }

  function section(index, section) {
    if (section instanceof Query) {
      let q = section[0];
      return render$1(index, q);
    } else if (section instanceof Paragraph) {
      let content = section[0];
      return p(toList([]), toList([text(content)]));
    } else {
      throw makeError(
        "case_no_match",
        "datalog/browser/view/page",
        29,
        "",
        "No case clause matched",
        { values: [section] }
      )
    }
  }

  function render(model) {
    if (!(model instanceof Model)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/page",
        10,
        "render",
        "Assignment pattern did not match",
        { value: model }
      )
    }
    let sections = model.sections;
    return div(
      toList([class$("vstack wrap")]),
      toList([
        div(
          toList([class$("absolute  bottom-0 left-0 right-0 top-0")]),
          toList([]),
        ),
        div(
          toList([class$("absolute border p-4 bg-white w-full max-w-xl rounded")]),
          toList([
            p(toList([]), toList([text("floating modal")])),
            p(toList([]), toList([text("floating modal")])),
          ]),
        ),
        div(
          toList([
            attribute("tabindex", "-1"),
            class$("vstack w-full max-w-2xl mx-auto"),
          ]),
          index_map(sections, section),
        ),
      ]),
    );
  }

  function init(_) {
    return initial();
  }

  function update(model, msg) {
    return msg(model);
  }

  function run() {
    let app = simple(init, update, render);
    let $ = start(app, "body > *", undefined);
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/app",
        7,
        "run",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    return undefined;
  }

  run();

})();
