package generated

//go:generate go run ../transpile.go ../../../test/environment_capture.json

type K = func(any)

func then(value any, k K) {
	k(value)
}

type empty struct {
}
