import { Map, Stack } from "immutable";

const VAR = "v"
const LAMBDA = "f"
const APPLY = "a"
const LET = "l"
const VACANT = "z"

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
        this.setValue(getVariable(this.env, expression.l))
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
        this.break = new Error("not implemented");
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
        this.setValue(partial(expression, builtin(expression.l)))
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
        this.push(new Apply(value))
        this.env = kont.env
        this.setExpression(kont.arg)
        break;
      case Apply:
        let { func } = kont
        this.call(func, value)
        break;
      case Call:
        let { arg } = kont
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
  constructor(func) {
    this.func = func
  }
}

class Call {
  constructor(arg) {
    this.arg = arg
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

function getVariable(env, label) {
  let value = env.get(label)
  if (value === undefined) this.break = new Error("missing variable: " + label)
  return value
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

const builtins = {
  int_add(a, b) { this.setValue(a + b) },
  int_subtract(a, b) { this.setValue(a - b) }
}

function builtin(identifier) {
  let value = builtins[identifier]
  if (value === undefined) this.break = new Error("unknown builtin: " + identifier)
  return value
}