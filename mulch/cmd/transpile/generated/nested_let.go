package testdata

func Run(done func(any)) {
	then(5, func(x any) {
		then(2, func(x any) {
			then(x, done)
		})
	})
}

// func R()  {
// 	I(5)
// 	.then(func(x any) {

// 	})
// }
