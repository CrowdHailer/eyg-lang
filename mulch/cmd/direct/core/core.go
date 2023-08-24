package core

type record interface {
	get(string) any
}
type empty struct {
}

func (*empty) get(string) any {
	panic("field not found")
}

type extend struct {
	label string
	value any
	rest  record
}

func (r *extend) get(label string) any {
	if label == r.label {
		return (r.value)
	}
	return r.rest.get(label)
}

func Empty() any {
	return &empty{}
}

type Tagged struct {
	Label string
	Value any
}

func Tag(label string) any {
	return func(value any) any {
		return &Tagged{Label: label, Value: value}
	}
}

// var Extrinsic = make(map[string]func(any) any)

func Perform(label string) any {
	return func(value any) any {
		// action, ok := Extrinsic[label]
		// if !ok {
		// 	panic(fmt.Sprintf("unknown handler %s", label))
		// }
		// return action(value)
		return Empty()
	}
}
