package generated

//go:generate go run ../transpile.go ../../../test/param_in_env.json
//go:generate go run ../transpile.go ../../../test/environment_capture.json
//go:generate go run ../transpile.go ../../../test/nested_let.json
//go:generate go run ../transpile.go ../../../test/nested_apply.json

//go:generate go run ../transpile.go ../../../test/records/record_select.json

type K = func(any)

func then(value any, k K) {
	k(value)
}
func block(b func(K)) any {
	var result any
	b(func(v any) { result = v })
	return result
}

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

func __empty() any {
	return &empty{}
}

func __extend(label string) any {
	return func(v any, k K) {
		field := v
		k(func(v any, k K) {
			record := v.(record)
			k(&extend{label, field, record})
		})
	}
}

func __select(label string) any {
	return func(v any, k K) {
		record := v.(record)
		k(record.get(label))
	}
}

func int_add(v any, k K) {
	x := v.(int)
	k(func(v any, k K) {
		y := v.(int)
		k(x + y)
	})
}
func int_subtract(v any, k K) {
	x := v.(int)
	k(func(v any, k K) {
		y := v.(int)
		k(x - y)
	})
}
