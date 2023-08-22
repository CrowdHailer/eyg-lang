package transpiled

import "mulch/cmd/direct/core"

func EnvironmentCapture() any {
	var a0 any = 1
	_ = a0
	var f1 any = func(_2 any) any {
		return a0
	}
	_ = f1
	var a3 any = 2
	_ = a3
	return f1.(func(any) any)(core.Empty())
}
