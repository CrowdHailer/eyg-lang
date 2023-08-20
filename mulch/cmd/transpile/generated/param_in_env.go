package generated

func ParamInEnv(_k K) {
	then(1, func(a any) {
		then(func(a any, _k K) {
			then(a, _k)
		}, func(f any) {
			then(f, func(_fn any) {
				then(2, func(_arg any) {
					_fn.(func(any, K))(_arg, _k)
				})
			})
		})
	})
}
