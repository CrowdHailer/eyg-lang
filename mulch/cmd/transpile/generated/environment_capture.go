package generated

func EnvironmentCapture(_k K) {
	then(1, func(a any) {
		then(func(_ any, _k K) {
			then(a, _k)
		}, func(f any) {
			then(2, func(a any) {
				then(f, func(_fn any) {
					then(__empty(), func(_arg any) {
						_fn.(func(any, K))(_arg, _k)
					})
				})
			})
		})
	})
}
