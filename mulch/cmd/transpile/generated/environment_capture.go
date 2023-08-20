package generated

func EnvironmentCapture(_k K) {
	then(1, func(a any) {
		then(func(_ any, _k K) {
			then(a, _k)
		}, func(f any) {
			then(2, func(a any) {
				f.(func(any, K))(empty{}, _k)
			})
		})
	})
}
