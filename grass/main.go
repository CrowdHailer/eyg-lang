package main

import (
	"fmt"
	"strings"
)

// Need persistent datastructures for env

func main() {
	var source Expression
	fmt.Println("")
	source = String{value: "hello"}
	result := interpretWithStd(source)
	fmt.Printf("%#v\n", result)

	source = Let{"x", source, Var{"x"}}
	result = interpretWithStd(source)
	fmt.Printf("%#v\n", result)

	source = Apply{Var{"uppercase"}, Apply{Fn{"x", Var{"x"}}, String{value: "blue"}}}

	result = interpretWithStd(source)
	fmt.Printf("%#v\n", result)

	source = Apply{Apply{Cons{}, String{value: "item"}}, Tail{}}

	result = interpretWithStd(source)
	fmt.Printf("%#v\n", result)

	// let server request -> dom -> dom.alert(request.method)
	// let bar = foo(x)
	// let sourceCode = serialize(bar)
	// astToJSON(sourceCode)
	// Don't AST but capture runtime. but how do I do this with hash reference
	// let framework(f) {
	// 	let client = f(request)
	// 	serialize(client)
	// }

}

// List AST   n = 1 and expression n > 1 is apply n = 0 unit/tail

// func step(exp Expression, env Env) {
// 	switch t := exp.(type) {
// 	case Let:
// 		a := t.label
// 		a
// 	}
// }

type Value interface {
	Call(Value, K) Cont
}

type defaultValue struct {
}

func (defaultValue) Call(Value, K) Cont {
	panic("not a function")
}

type Env = map[string]Value

type K = func(Value) Cont

type Cont struct {
	value Value
	k     func(Value) Cont
}

func interpretWithStd(e Expression) Value {
	env := map[string]Value{
		"uppercase": Uppercase{},
	}
	return interpret(e, env)
}

func interpret(e Expression, env Env) Value {
	var c Cont = e.Step(env, nil)
	for {
		if c.k == nil {
			break
		}
		c = c.k(c.value)
	}
	return c.value
}

type Expression interface {
	Step(Env, K) Cont
}

type Fn struct {
	param string
	body  Expression
}

func (fn Fn) Step(env Env, k K) Cont {
	return Cont{value: RunFn{fn, env}, k: k}
}

type RunFn struct {
	fn  Fn
	env Env
}

func (runFn RunFn) Call(arg Value, k K) Cont {
	// TODO proper copy
	env := make(map[string]Value, 0)
	for k, v := range runFn.env {
		env[k] = v
	}
	env[runFn.fn.param] = arg
	return runFn.fn.body.Step(env, k)
	// return Env
}

// Actual builtins
type Uppercase struct {
}

func (builtin Uppercase) Call(arg Value, k K) Cont {
	t, ok := arg.(String)
	if !ok {
		panic("bad arg to 'uppercase'")
	}
	term := String{value: strings.ToUpper(t.value)}
	return Cont{value: term, k: k}
}

type Apply struct {
	fn  Expression
	arg Expression
}

func (a Apply) Step(env Env, k K) Cont {
	return a.fn.Step(env, func(fn Value) Cont {
		return a.arg.Step(env, func(arg Value) Cont {
			return fn.Call(arg, k)
		})
	})
}

type Let struct {
	label string
	value Expression
	then  Expression
}

func (l Let) Step(env Env, k K) Cont {
	return l.value.Step(env, func(v Value) Cont {
		env[l.label] = v
		return l.then.Step(env, k)
	})
}

type Var struct {
	label string
}

func (v Var) Step(env Env, k K) Cont {
	value, ok := env[v.label]
	if !ok {
		panic("bad value")
	}
	return Cont{value: value, k: k}
}

type String struct {
	defaultValue
	value string
}

func (s String) Step(_ Env, k K) Cont {
	return Cont{value: s, k: k}
}

type Tail struct {
	defaultValue
}

func (t Tail) Step(_ Env, k K) Cont {
	return Cont{value: t, k: k}
}

type Cons struct {
	defaultValue
	item Value
	rest Value
}

func (c Cons) Step(_ Env, k K) Cont {
	return Cont{value: c, k: k}
}

func (c Cons) Call(v Value, k K) Cont {
	// Check nilness
	if c.item == nil {
		// TODO need to copy
		c.item = v
		return Cont{c, k}
	}
	if c.rest == nil {
		// TODO need to copy
		c.rest = v
		return Cont{c, k}
	}
	return c.defaultValue.Call(v, k)
}
