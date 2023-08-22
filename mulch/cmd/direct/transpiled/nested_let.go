package transpiled

import "mulch/cmd/direct/core"

func NestedLet() any {
	var a0 any = func() any {
		var a1 any = 2
		_ = a1
		return 1
	}()
	_ = a0
	return a0
}
