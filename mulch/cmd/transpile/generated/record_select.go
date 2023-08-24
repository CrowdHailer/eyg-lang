package generated

func RecordSelect(_k K) {
	then(__extend("x"), func(_fn any) {
		then("hey", func(_arg any) {
			_fn.(func(any, K))(_arg, func(_fn any) {
				then(__empty(), func(_arg any) {
					_fn.(func(any, K))(_arg, func(a any) {
						then(__select("x"), func(_fn any) {
							then(a, func(_arg any) {
								_fn.(func(any, K))(_arg, _k)
							})
						})
					})
				})
			})
		})
	})
}
