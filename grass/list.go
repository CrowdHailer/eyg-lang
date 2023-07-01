package main

import "fmt"

type Cons struct {
	item Value
	// should be a value
	tail Value
}

// TODO need immutable refs
func (c Cons) call(arg Value, env *Env, k Kont) (Expression, *Env, Kont, error) {
	if c.item == nil {
		c.item = arg
		return &Term{c}, env, k, nil
	}
	// this allows improper lists could fix and bunch onto real list
	// Don't have tail in cons should return new data type
	if c.tail == nil {
		c.tail = arg
		return &Term{c}, env, k, nil
	}
	return &Term{c}, env, k, fmt.Errorf("cannot call a list")
}
