package mulch

import "fmt"

type Integer struct {
	value int32
}

var _ Value = (*Integer)(nil)

func (i *Integer) step(e E, k K) (C, E, K) {
	return k.compute(i, e)
}

func (i *Integer) call(_arg Value, env E, k K) (C, E, K) {
	return &Error{&NotAFunction{i}}, env, k
}

func (i *Integer) Debug() string {
	return fmt.Sprintf("%d", i.value)
}
