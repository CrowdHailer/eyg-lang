package fern

func zipper(source Node, path []int) (func(Node) Node, error) {
	tree := source
	var bs []func(Node) Node
	for _, p := range path {
		t, b, err := tree.child(p)
		tree = t
		if err != nil {
			return nil, err
		}
		bs = append(bs, b)
	}
	return func(n Node) Node {
		for i := len(bs) - 1; i >= 0; i-- {
			n = bs[i](n)
		}
		return n
	}, nil
}
