package main

import "fmt"

type Perform struct {
	label string
	lift  Value
	k     Kont
}

func (p Perform) call(arg Value, env *Env, k Kont) (Expression, *Env, Kont, error) {
	if p.lift == nil {
		p.lift = arg
		p.k = k
		return &Term{p}, env, nil, nil
	}
	return &Term{p}, env, k, fmt.Errorf("should not be able to call perform")
}

type Shallow struct {
	label   string
	handler Value
	k       Kont
}

func (p Shallow) call(arg Value, env *Env, k Kont) (Expression, *Env, Kont, error) {
	if p.handler == nil {
		p.handler = arg
		p.k = k
		return &Term{p}, env, nil, nil
	}
	return &Term{p}, env, k, fmt.Errorf("should not be able to call perform")

}

// difference in evalling exec and looking at response vs passing handlers through
