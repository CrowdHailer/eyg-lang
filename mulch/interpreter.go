package mulch

import "fmt"

type C interface {
	step(E, K) (C, E, K)
}

type Value interface {
	C
	call(Value, E, K) (C, E, K)
	Debug() string
}
type Exp interface {
	C
	MarshalJSON() ([]byte, error)
}

type E interface {
	get(string) (Value, bool)
	put(string, Value) E
}

// K exists so I don't have to track that I have pointers to the stack
type K interface {
	compute(v Value, e E) (C, E, K)
	done() bool
}

type Lambda struct {
	Label string
	Body  Exp
}

func (lambda *Lambda) step(e E, k K) (C, E, K) {
	return &Closure{lambda, e}, e, k
}

type Closure struct {
	lambda *Lambda
	env    E
}

func (closure *Closure) step(e E, k K) (C, E, K) {
	return k.compute(closure, e)
}

func (c *Closure) call(arg Value, _ E, k K) (C, E, K) {
	e := c.env.put(c.lambda.Label, arg)
	return c.lambda.Body, e, k
}

func (c *Closure) Debug() string {
	return fmt.Sprintf("(%s) -> { ... }", c.lambda.Label)
}

type Call struct {
	Fn  Exp
	Arg Exp
}

func (exp *Call) step(e E, k K) (C, E, K) {
	return exp.Fn, e, &Stack{&Arg{exp.Arg, e}, k}
}

type Variable struct {
	Label string
}

func (exp *Variable) step(e E, k K) (C, E, K) {
	value, ok := e.get(exp.Label)
	if !ok {
		return &Error{&UndefinedVariable{exp.Label}}, e, k
	}
	return value, e, k
}

type Let struct {
	Label string
	Value Exp
	Then  Exp
}

func (exp *Let) step(e E, k K) (C, E, K) {
	return exp.Value, e, &Stack{&Assign{exp.Label, exp.Then, e}, k}
}

type Assign struct {
	label string
	then  Exp
	env   E
}

func (k *Assign) compute(value Value, _ E, rest K) (C, E, K) {
	e := k.env.put(k.label, value)
	return k.then, e, rest
}

type Arg struct {
	value Exp
	env   E
}

func (k *Arg) compute(value Value, _ E, rest K) (C, E, K) {
	return k.value, k.env, &Stack{&Apply{value, k.env}, rest}
}

type Apply struct {
	Fn  Value
	Env E
}

func (k *Apply) compute(value Value, env E, rest K) (C, E, K) {
	return k.Fn.call(value, k.Env, rest)
}

type Vacant struct {
	comment string
}

var _ C = (*Vacant)(nil)

func (v *Vacant) step(e E, k K) (C, E, K) {
	return &Error{&NotImplemented{v.comment}}, e, k
}

func Eval(c C, k K) (Value, *Error) {
	var e E = emptyEnv()
	for {
		if err, ok := c.(*Error); ok {
			return nil, err
		}
		if value, ok := c.(Value); ok && k.done() {
			return value, nil
		}
		c, e, k = c.step(e, k)
	}
}

func EvalResumable(c C, k K) (Value, *Error, E, K) {
	var e E = emptyEnv()
	return ContinueEval(c, e, k)
}

func ContinueEval(c C, e E, k K) (Value, *Error, E, K) {
	for {
		if err, ok := c.(*Error); ok {
			return nil, err, e, k
		}
		if value, ok := c.(Value); ok && k.done() {
			return value, nil, e, k
		}
		c, e, k = c.step(e, k)
	}
}
