package main

import "fmt"

type Value interface {
	call(Value, *Env, Kont) (Expression, *Env, Kont, error)
}

type Expression interface {
	step(*Env, Kont) (Expression, *Env, Kont, error)
}

type Kont interface {
	resume(Value, *Env) (Expression, *Env, Kont, error)
}

func resume(k Kont, value Value, env *Env) (Expression, *Env, Kont, error) {
	if k == nil {
		return &Term{value}, env, nil, nil
	}
	return k.resume(value, env)
}

// needed for handle
func eval(exp Expression, k Kont) (Value, error) {
	env := emptyEnv()
	// var k Kont = nil
	var err error = nil
	for {
		if term, ok := exp.(*Term); ok && k == nil {
			return term.value, nil
		}
		exp, env, k, err = exp.step(env, k)
		if err != nil {
			return nil, err
		}
	}
}

type Term struct {
	value Value
}

func (exp *Term) step(env *Env, k Kont) (Expression, *Env, Kont, error) {
	return resume(k, exp.value, env)
}

type Variable struct {
	label string
}

func (exp *Variable) step(env *Env, k Kont) (Expression, *Env, Kont, error) {
	value, ok := env.get(exp.label)
	if !ok {
		return exp, env, k, fmt.Errorf("unbound variable")
	}
	return resume(k, value, env)
}

type Lambda struct {
	label string
	body  Expression
}

func (exp *Lambda) step(env *Env, k Kont) (Expression, *Env, Kont, error) {
	closure := &Closure{exp.label, exp.body, env}
	return resume(k, closure, env)
}

type Call struct {
	fn  Expression
	arg Expression
}

func (exp *Call) step(env *Env, k Kont) (Expression, *Env, Kont, error) {
	return exp.fn, env, &Arg{exp.arg, env, k}, nil
}

type Let struct {
	label string
	value Expression
	then  Expression
}

func (exp *Let) step(env *Env, k Kont) (Expression, *Env, Kont, error) {
	return exp.value, env, &Assign{exp.label, exp.then, k}, nil
}

// K's --------
type Assign struct {
	label string
	then  Expression
	k     Kont
}

var _ Kont = (*Assign)(nil)

func (k *Assign) resume(value Value, env *Env) (Expression, *Env, Kont, error) {
	env = env.push(k.label, value)
	return k.then, env, k.k, nil
}

type Arg struct {
	value Expression
	env   *Env
	k     Kont
}

var _ Kont = (*Arg)(nil)

func (k *Arg) resume(value Value, env *Env) (Expression, *Env, Kont, error) {
	return k.value, k.env, &Apply{value, k.k}, nil
}

type Apply struct {
	fn Value
	k  Kont
}

func (k *Apply) resume(value Value, env *Env) (Expression, *Env, Kont, error) {
	return k.fn.call(value, env, k.k)
}

type Closure struct {
	label string
	body  Expression
	env   *Env
}

func (c *Closure) call(arg Value, env *Env, k Kont) (Expression, *Env, Kont, error) {
	env = env.push(c.label, arg)
	return c.body, env, k, nil
}

// TODO is there a nice way to express pulling off of a linear AST stack
// closures that we can demo lambda calculus
