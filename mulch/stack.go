package mulch

import "fmt"

type Stack struct {
	K    k
	Rest K
}

type Done struct {
	External map[string]func(Value) C
}

var _ K = (*Stack)(nil)
var _ K = (*Done)(nil)

func (s *Stack) compute(v Value, e E) (C, E, K) {
	var rest K = s.Rest
	return s.K.compute(v, e, rest)
}
func (*Done) compute(v Value, e E) (C, E, K) {
	panic("tried to compute with an empty stack")
}

func (s *Stack) done() bool {
	switch s.K.(type) {
	case *Shallow, *Handle:
		return s.Rest.done()
	}
	return false
}
func (*Done) done() bool {
	return true
}

type k interface {
	compute(value Value, e E, rest K) (C, E, K)
}

func stacktrace(k K) {
	i := 0
	for {
		if _, ok := k.(*Done); ok {
			fmt.Printf("[%3d] Done\n", i)
			return
		}
		stack := k.(*Stack)
		switch line := stack.K.(type) {
		case *Assign:
			fmt.Printf("[%3d] Assign %s\n", i, line.label)
		case *Arg:
			fmt.Printf("[%3d] Arg fn %f\n", i, line.value)
		case *Apply:
			fmt.Printf("[%3d] Call fn %s\n", i, line.Fn.Debug())
		case *CallWith:
			fmt.Printf("[%3d] Call with arg %s\n", i, line.Value.Debug())
		case *Shallow:
			fmt.Printf("[%3d] Shallow %s\n", i, line.label)
		case *Handle:
			fmt.Printf("[%3d] Deep %s\n", i, line.label)
		default:
			fmt.Printf("[%3d] %#v\n", i, stack.K)
		}
		k = stack.Rest
		i++
	}
}
