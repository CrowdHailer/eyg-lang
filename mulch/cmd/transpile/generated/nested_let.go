package generated

func NestedLet(_k K) {
	then(2, func(a any) {
		then(1, func(a any) {
			then(a, _k)
		})
	})
}
