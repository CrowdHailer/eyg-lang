package testdata

func bob() {
	func(a any) {
		func(f any) {
			func(a any) {
				f.(func(any) any)(empty{})
			}(2)
		}(panic(""))
	}(1)
}

type empty struct {
}
