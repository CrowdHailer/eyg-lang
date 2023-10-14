package main

import "mulch/cmd/direct/core"

func Source() any {
	var _0 any = __perform("LED").(func(any) any)(core.Tag("True").(func(any) any)(core.Empty()))
	_ = _0
	var _1 any = __perform("Wait").(func(any) any)(500)
	_ = _1
	var _2 any = __perform("LED").(func(any) any)(core.Tag("False").(func(any) any)(core.Empty()))
	_ = _2
	var _3 any = __perform("Wait").(func(any) any)(200)
	_ = _3
	return core.Empty()
}
