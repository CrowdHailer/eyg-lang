package mulch

import "fmt"

type Promise struct {
	Value <-chan Value
}

var _ Value = (*Promise)(nil)

func (p *Promise) step(e E, k K) (C, E, K) {
	return k.compute(p, e)
}

func (p *Promise) call(_arg Value, env E, k K) (C, E, K) {
	return &Error{&NotAFunction{p}}, env, k
}

func (p *Promise) Debug() string {
	// TODO peek
	return fmt.Sprintf("Promise %d", p.Value)
}
