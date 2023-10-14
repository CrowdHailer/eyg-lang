package trifle

type Cons struct {
	Head any
	Tail any
}

type Tail struct {
}

func Cons0(h any) func(any) any {
	return func(t any) any {
		return &Cons{h, t}
	}
}
