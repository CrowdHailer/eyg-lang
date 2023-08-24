package transpiled

//go:generate go run ../direct.go ../../../test/param_in_env.json transpiled
//go:generate go run ../direct.go ../../../test/environment_capture.json transpiled
//go:generate go run ../direct.go ../../../test/nested_let.json transpiled

// func __extend(label string) any {
// 	return func(v any, k K) {
// 		field := v
// 		k(func(v any, k K) {
// 			record := v.(record)
// 			k(&extend{label, field, record})
// 		})
// 	}
// }

// func __select(label string) any {
// 	return func(v any, k K) {
// 		record := v.(record)
// 		k(record.get(label))
// 	}
// }

// func int_add(v any, k K) {
// 	x := v.(int)
// 	k(func(v any, k K) {
// 		y := v.(int)
// 		k(x + y)
// 	})
// }
// func int_subtract(v any, k K) {
// 	x := v.(int)
// 	k(func(v any, k K) {
// 		y := v.(int)
// 		k(x - y)
// 	})
// }
