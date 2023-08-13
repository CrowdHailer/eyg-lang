package mulch

import "fmt"

type Tag struct {
	label string
	value Value
}

func (value *Tag) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *Tag) call(arg Value, e E, k K) (C, E, K) {
	if value.value == nil {
		new := *value
		new.value = arg
		return &new, e, k
	}
	return &Error{&NotAFunction{value}}, e, k
}

func (value *Tag) Debug() string {
	if value.value == nil {
		return value.label
	}
	return fmt.Sprintf("%s(%s)", value.label, value.value.Debug())
}

type Case struct {
	label     string
	branch    Value
	otherwise Value
}

func (value *Case) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (case_ *Case) call(arg Value, e E, k K) (C, E, K) {
	if case_.branch == nil {
		new := *case_
		new.branch = arg
		return &new, e, k
	}
	if case_.otherwise == nil {
		new := *case_
		new.otherwise = arg
		return &new, e, k
	}
	tagged, ok := arg.(*Tag)
	if !ok {
		return &Error{&NotATagged{arg}}, e, k
	}
	if tagged.label == case_.label {
		return case_.branch.call(tagged.value, e, k)
	}
	return case_.otherwise.call(tagged, e, k)
}

func (value *Case) Debug() string {
	return fmt.Sprintf("case %s", value.label)
}

type NoCases struct{}

func (value *NoCases) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *NoCases) call(arg Value, e E, k K) (C, E, K) {
	return &Error{&NoMatch{}}, e, k
}

func (value *NoCases) Debug() string {
	return "nocases"
}
