package generated

//go:generate go run ../transpile.go ../../../test/param_in_env.json
//go:generate go run ../transpile.go ../../../test/environment_capture.json
//go:generate go run ../transpile.go ../../../test/nested_let.json
//go:generate go run ../transpile.go ../../../test/nested_apply.json

type K = func(any)

func then(value any, k K) {
	k(value)
}
func block(b func(K)) any {
	var result any
	b(func(v any) { result = v })
	return result
}

type empty struct {
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
