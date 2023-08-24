package mulch

import "fmt"

type String struct {
	Value string
}

var _ Value = (*String)(nil)

func (s *String) step(e E, k K) (C, E, K) {
	return k.compute(s, e)
}

func (s *String) call(_arg Value, env E, k K) (C, E, K) {
	return &Error{&NotAFunction{s}}, env, k
}

func (s *String) Debug() string {
	return fmt.Sprintf(`"%s"`, s.Value)
}
