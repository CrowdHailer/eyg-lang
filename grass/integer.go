package main

import "fmt"

type Integer struct {
	foo int32
}

var _ Value = (*Integer)(nil)

func (i *Integer) call(_arg Value, env *Env, k Kont) (Expression, *Env, Kont, error) {
	return nil, env, k, fmt.Errorf("cannot call integer")
}
