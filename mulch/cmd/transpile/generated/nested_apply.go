package generated

func NestedApply(_k K) {
	then(int_subtract, func(_fn any) {
		then(int_add, func(_fn any) {
			then(3, func(_arg any) {
				_fn.(func(any, K))(_arg, func(_fn any) {
					then(4, func(_arg any) {
						_fn.(func(any, K))(_arg, func(_arg any) {
							_fn.(func(any, K))(_arg, func(_fn any) {
								then(int_add, func(_fn any) {
									then(1, func(_arg any) {
										_fn.(func(any, K))(_arg, func(_fn any) {
											then(2, func(_arg any) {
												_fn.(func(any, K))(_arg, func(_arg any) {
													_fn.(func(any, K))(_arg, _k)
												})
											})
										})
									})
								})
							})
						})
					})
				})
			})
		})
	})
}
