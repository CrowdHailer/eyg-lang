package mulch

import (
	"fmt"
	"strings"
)

type Tail struct {
}

func (tail *Tail) step(e E, k K) (C, E, K) {
	return k.compute(tail, e)
}

func (tail *Tail) call(_arg Value, e E, k K) (C, E, K) {
	return &Error{&NotAFunction{tail}}, e, k
}

func (tail *Tail) Debug() string {
	return "[]"
}

type Cons struct {
	item Value
	tail Value
}

func (i *Cons) step(e E, k K) (C, E, K) {
	return k.compute(i, e)
}

func (c *Cons) call(arg Value, env E, k K) (C, E, K) {
	if c.item == nil {
		d := *c
		d.item = arg
		return &d, env, k
	}
	// this allows improper lists could fix and bunch onto real list
	// Don't have tail in cons should return new data type
	if c.tail == nil {
		d := *c
		d.tail = arg
		return &d, env, k
	}
	return &Error{&NotAFunction{c}}, env, k
}

func (list *Cons) Debug() string {
	items := []string{}
out:
	for {
		if list.item == nil {
			items = append(items, "_")
		} else {
			items = append(items, list.item.Debug())
		}
		switch l := list.tail.(type) {
		case *Cons:
			list = l
		case *Tail:
			break out
		case nil:
			items = append(items, ".._")
			break out
		default:
			items = append(items, fmt.Sprintf("..%s", l.Debug()))
			break out
		}
	}
	return fmt.Sprintf("[%s]", strings.Join(items, ", "))
}
