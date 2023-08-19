package testdata

func Run() {
	func(a any) {
		func(f any) {
			func(a any) {
				f.(func(any) any)(empty{})
			}(2)
		}(ALm)
	}(1)
}
