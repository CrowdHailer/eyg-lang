package testdata

func then(any, func(any)) {
	panic("todo")
}

// Needs currying
func R(k func(any)) {
	then(1, func(_1 any) {
		then(2, func(_2 any) {
			add(_1, _2, func(_3 any) {
				then(3, func(_4 any) {
					add(_3, _4, k)
				})
			})
		})
	})
}

func add(v1, v2 any, k func(any)) {
	x := v1.(int)
	y := v2.(int)
	k(x + y)
}
