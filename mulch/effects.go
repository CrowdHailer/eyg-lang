package mulch

import (
	"fmt"
)

type Perform struct {
	Label string
}

func (i *Perform) step(e E, k K) (C, E, K) {
	return k.compute(i, e)
}

func (i *Perform) Debug() string {
	return fmt.Sprintf("^%s", i.Label)
}

type Resume struct {
	e        E
	reversed K
}

func (i *Resume) step(e E, k K) (C, E, K) {
	return k.compute(i, e)
}

func (r *Resume) call(arg Value, _ E, k K) (C, E, K) {
	reversed := r.reversed
	for {
		if _, ok := reversed.(*Done); ok {
			break
		}
		stack := reversed.(*Stack)
		k = &Stack{stack.k, k}
		reversed = stack.rest
	}
	return arg, r.e, k
}

func (i *Resume) Debug() string {
	return "resume"
}

type CallWith struct {
	value Value
}

func (k *CallWith) compute(v Value, e E, rest K) (C, E, K) {
	return v.call(k.value, e, rest)
}

func (p *Perform) call(lift Value, e E, k K) (C, E, K) {
	// Perform should start executing the handler in the env context of the handler
	outer := k
	// reversed is inner
	var reversed K = &Done{}
	for {
		switch stack := outer.(type) {
		case *Done:
			handler, ok := stack.External[p.Label]
			if !ok {
				return &Error{&UnhandledEffect{p.Label, lift}}, e, k
			}
			return handler(lift), e, k
		case *Stack:
			current := stack.k
			outer = stack.rest
			if delimiter, ok := current.(*Handle); ok && delimiter.label == p.Label {
				reversed = &Stack{current, reversed}
				resume := &Resume{e, reversed}
				return delimiter.handle, delimiter.e, &Stack{&CallWith{lift}, &Stack{&CallWith{resume}, outer}}
			}
			if delimiter, ok := current.(*Shallow); ok && delimiter.label == p.Label {
				resume := &Resume{e, reversed}
				return delimiter.handle, delimiter.e, &Stack{&CallWith{lift}, &Stack{&CallWith{resume}, outer}}
			}
			reversed = &Stack{current, reversed}
		default:
			panic("unknown stack")
		}
	}
}

type Shallow struct {
	label  string
	handle Value
	e      E
	k      K
}

func (i *Shallow) step(e E, k K) (C, E, K) {
	return k.compute(i, e)
}

func (value *Shallow) call(arg Value, e E, k K) (C, E, K) {
	if value.handle == nil {
		new := *value
		new.handle = arg
		return &new, e, k
	}
	if value.k == nil {
		new := *value
		new.e = e
		new.k = k
		return arg, e, &Stack{&CallWith{&Empty{}}, &Stack{&new, k}}
	}
	panic("shouldnt get here")
}
func (i *Shallow) Debug() string {
	return fmt.Sprintf("shallow %s", i.label)
}

func (i *Shallow) compute(v Value, e E, rest K) (C, E, K) {
	return rest.compute(v, e)
}

type Handle struct {
	label  string
	handle Value
	e      E
	k      K
}

func (i *Handle) step(e E, k K) (C, E, K) {
	return k.compute(i, e)
}

func (value *Handle) call(arg Value, e E, k K) (C, E, K) {
	// because eval ing
	if value.handle == nil {
		new := *value
		new.handle = arg
		return &new, e, k
	}
	if value.k == nil {
		new := *value
		new.e = e
		new.k = k
		return arg, e, &Stack{&CallWith{&Empty{}}, &Stack{&new, k}}
	}
	panic("not doing shouldnt get here yet")
}

func (i *Handle) Debug() string {
	if i.handle != nil {
		return fmt.Sprintf("deep %s(%s)", i.label, i.handle.Debug())

	}
	return fmt.Sprintf("deep %s", i.label)
}

func (i *Handle) compute(v Value, e E, rest K) (C, E, K) {
	return rest.compute(v, e)
}
