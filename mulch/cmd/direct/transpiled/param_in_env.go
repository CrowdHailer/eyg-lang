package transpiled

import "mulch/cmd/direct/core"

func ParamInEnv() any {
	var a0 any = 1
	_ = a0
	var f1 any = func(a2 any) any {
		return a2
	}
	_ = f1
	return f1.(func(any) any)(2)
}
