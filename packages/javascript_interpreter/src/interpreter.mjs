import { Map, Stack } from "immutable";

const VAR = "v"
const LAMBDA = "f"
const APPLY = "a"
const LET = "l"
const VACANT = "z"

const Binary = "x"
const INT = "i"
const STRING = "s"

const TAIL = "ta"
const CONS = "c"

const EMPTY = "u"
const EXTEND = "e"
const SELECT = "g"
const OVERWRITE = "o"

const TAG = "t"
const CASE = "m"
const NOCASES = "n"

const PERFORM = "p"
const HANDLE = "h"

const BUILTIN = "b"

const tail = Stack()
const empty = Map()

class State {
  value = false
  env = Map()
  stack = Stack()

  constructor(src) {
    this.control = src
  }

  setValue(value) {
    this.value = true, this.control = value
  }

  setExpression(expression) {
    this.value = false, this.control = expression
  }

  getVariable(env, label) {
    let value = env.get(label)
    if (value === undefined) this.break = { UndefinedVariable: label }
    return value
  }

  builtin(identifier) {
    let value = builtins[identifier]
    if (value === undefined) this.break = { UndefinedBuiltin: identifier }
    return value
  }

  push(kont) {
    this.stack = this.stack.push(kont)
  }

  step() {
    this.value ? this.apply() : this.eval();
  }

  eval() {
    let expression = this.control
    switch (expression[0]) {
      case VAR:
        this.setValue(this.getVariable(this.env, expression.l))
        break;
      case LAMBDA:
        this.setValue(new Closure(expression, this.env))
        break;
      case APPLY:
        this.push(new Arg(expression.a, this.env))
        this.setExpression(expression.f)
        break;
      case LET:
        this.push(new Assign(expression.l, expression.t, this.env))
        this.setExpression(expression.v)
        break;
      case VACANT:
        this.break = { NotImplemented: "" };
      case Binary:
        this.setValue(expression.v)
        break;
      case INT:
        this.setValue(expression.v)
        break;
      case STRING:
        this.setValue(expression.v)
        break;
      case TAIL:
        this.setValue(tail)
        break;
      case CONS:
        this.setValue(partial(expression, cons))
        break;
      case EMPTY:
        this.setValue(empty)
        break;
      case EXTEND:
      case OVERWRITE:
        this.setValue(partial(expression, extend(expression.l)))
        break;
      case SELECT:
        this.setValue(partial(expression, select(expression.l)))
        break;
      case TAG:
        this.setValue(partial(expression, tag(expression.l)))
        break
      case CASE:
        this.setValue(partial(expression, case_(expression.l)))
        break;
      case NOCASES:
        this.setValue(partial(expression, nocases))
        break;
      case PERFORM:
        this.setValue(partial(expression, perform(expression.l)))
        break;
      case HANDLE:
        this.setValue(partial(expression, handle(expression.l)))
        break;
      case BUILTIN:
        this.setValue(partial(expression, this.builtin(expression.l)))
        break;
      default:
        this.break = new Error("unrecognised expression")
    }
  }

  apply() {
    let value = this.control
    let kont = this.stack.first()
    if (kont === undefined) return value;
    this.stack = this.stack.pop()

    switch (kont.constructor) {
      case Assign:
        this.env = this.env.set(kont.label, value)
        this.setExpression(kont.then)
        break;
      case Arg:
        this.push(new Apply(value, kont.env))
        this.env = kont.env
        this.setExpression(kont.arg)
        break;
      case Apply:
        let { func } = kont
        this.env = kont.env
        this.call(func, value)
        break;
      case Call:
        let { arg } = kont
        this.env = kont.env
        this.call(value, arg)
        break;
      case Delimit:
        break;
      default:
        this.break = new Error("invalid continuation poped from stack")
    }
  }

  call(func, arg) {
    switch (func.constructor) {
      case Closure:
        let { captured, lambda } = func
        this.env = captured.set(lambda.l, arg)
        this.setExpression(lambda.b)
        break;
      case Partial:
        let { exp, applied, impl } = func
        applied = applied.push(arg)

        if (applied.size === impl.length) {
          impl.apply(this, applied.reverse().toArray())
        } else {
          this.setValue(new Partial(exp, applied, impl))
        }
        break;
      case Resume:
        let { reversed } = func
        while (reversed.size > 0) {
          this.push(reversed.first())
          reversed = reversed.pop()
        }
        this.setValue(arg)
        break;
      default:
        console.log(func, "FUUNC")
        this.break = new Error("not a function")
    }
  }

  loop() {
    while (true) {
      this.step()
      if (this.break || this.value && this.stack.size === 0) return this.control;
    }
  }

  resume(value) {
    this.setValue(value)
    this.break = undefined
    this.loop()
  }
}

class Closure {
  constructor(lambda, captured) {
    this.lambda = lambda, this.captured = captured
  }
}

class Partial {
  constructor(exp, applied, impl) {
    this.exp = exp, this.applied = applied, this.impl = impl
  }
}

function partial(exp, impl) {
  return new Partial(exp, Stack(), impl)
}

export class Tagged {
  tag
  inner
  constructor(tag, inner) {
    this.tag = tag
    this.inner = inner
  }
}

class Resume {
  constructor(reversed) {
    this.reversed = reversed
  }
}


class Arg {
  constructor(arg, env) {
    this.arg = arg, this.env = env
  }
}

class Apply {
  constructor(func, env) {
    this.func = func, this.env = env
  }
}

class Call {
  constructor(arg, env) {
    this.arg = arg, this.env = env
  }
}


class Assign {
  constructor(label, then, env) {
    this.label = label, this.then = then, this.env = env
  }
}

class Delimit {
  constructor(label, handle) {
    this.label = label, this.handle = handle
  }
}

export function eval_(src) {
  let state = new State(src)
  state.loop()
  return state
}

function cons(item, tail) {
  this.setValue(tail.push(item))
}

function extend(label) {
  return function (value, rest) {
    this.setValue(rest.set(label, value))
  }
}

function select(label) {
  return function (record) {
    let value = record.get(label)
    if (value === undefined) this.break = new Error("missing label: " + label)
    this.setValue(value)
  }
}
function tag(label) {
  return function (value) {
    this.setValue(new Tagged(label, value))
  }
}


function case_(label) {
  return function (branch, otherwise, value) {
    if (!value instanceof Tagged) this.break = new Error("Not a Tagged value")
    let { tag, inner } = value
    if (tag == label) {
      this.call(branch, inner)
    } else {
      this.call(otherwise, value)
    }
  }
}

function nocases(value) {
  console.log(value)
  this.break = new Error("no cases matched");
}

function perform(label) {
  return function (lift) {
    let stack = this.stack
    let reversed = Stack()
    let found;
    while (stack.size > 0) {
      let kont = stack.first()
      stack = stack.pop()
      reversed = reversed.push(kont)
      if (kont instanceof Delimit && kont.label === label) {
        found = kont
        break
      }
    }
    if (found) {
      this.stack = stack
      this.push(new Call(new Resume(reversed)))
      this.call(found.handle, lift)
    } else {
      this.break = new Effect(label, lift)
    }
  }
}

export class Effect {
  constructor(label, lift) {
    this.label = label, this.lift = lift
  }
}

function handle(label) {
  return function (handle, exec) {
    this.push(new Delimit(label, handle))
    this.call(exec, empty)
  }
}

const True = new Tagged("True", empty)
const False = new Tagged("False", empty)

function Ok(value) {
  return new Tagged("Ok", value)
}

function Error(value) {
  return new Tagged("Error", value)
}


const builtins = {
  equal(a, b) {
    let isEqual = a.equals ? a.equals(b) : a == b;
    this.setValue(isEqual ? True : False)
  },
  fix(builder) {
    this.push(new Call(new Partial({
      0: BUILTIN, l: "fixed"
    },
      Stack([builder]), fixed), this.env))
    this.setValue(builder)
  },
  int_compare(a, b) {
    let value
    if (a < b) {
      value = new Tagged("Lt", empty)
    } else if (a > b) {
      value = new Tagged("Gt", empty)
    } else {
      value = new Tagged("Eq", empty)
    }
    this.setValue(value)
  },
  int_add(a, b) { this.setValue(a + b) },
  int_subtract(a, b) { this.setValue(a - b) },
  int_multiply(a, b) { this.setValue(a * b) },
  int_divide(a, b) {
    let value = b == 0 ? Error(empty) : Ok(Math.floor(a / b))
    this.setValue(value)
  },
  int_absolute(a) { this.setValue(Math.abs(a)) },
  int_parse(a) {
    let n = Math.floor(Number(a))
    let value = isNaN(n) ?
      Error(empty) :
      a == n.toString() ?
        Ok(n) : Error(empty)
    this.setValue(value)
  },
  int_to_string(a) { this.setValue(a.toString()) },
  string_append(a, b) { this.setValue(a + b) },
  string_split(a, b) {
    let [head, ...tail] = a.split(b)
    this.setValue(Map({ head, tail: Stack(tail) }))
  },
  string_split_once(a, b) {
    let i = a.indexOf(b)
    let value = i < 0 ? Error(empty) : Ok(Map({ pre: a.slice(0, i), post: a.slice(i + b.length) }))
    this.setValue(value)
  },
  string_replace(a, b, c) { this.setValue(a.replaceAll(b, c)) },
  string_uppercase(a) { this.setValue(a.toUpperCase()) },
  string_lowercase(a) { this.setValue(a.toLowerCase()) },
  string_ends_with(a, b) { this.setValue(a.endsWith(b) ? True : False) },
  string_starts_with(a, b) { this.setValue(a.startsWith(b) ? True : False) },

  string_length(a) { this.setValue(a.length) },
  string_to_binary(a) {
    let encoder = new TextEncoder()
    this.setValue(encoder.encode(a))
  },
  string_from_binary(a) {
    let decoder = new TextDecoder("utf-8", { fatal: true })
    let value
    try {
      value = Ok(decoder.decode(a))
    } catch (error) {
      value = Error(empty)
    }
    this.setValue(value)
  },
  list_pop(a) {
    let item = a.first()
    this.setValue(item ? Ok(Map({ head: item, tail: a.shift() })) : Error(empty))
  },
  list_fold: list_fold
}

function fixed(builder, arg) {
  this.push(new Call(arg, this.env))
  this.push(new Call(new Partial({
    0: BUILTIN, l: "fixed"
  },
    Stack([builder]), fixed), this.env))
  this.setValue(builder)
}

function list_fold(list, state, func) {
  let item = list.first()
  if (item == undefined) {
    this.setValue(state)
  } else {
    this.push(new Call(func, this.env))
    this.push(new Apply(new Partial({
      0: BUILTIN, l: "list_fold"
    },
      Stack([list.shift()]), list_fold), this.env))
    this.push(new Call(state, this.env))
    this.push(new Call(item, this.env))
    this.setValue(func)
  }
}
