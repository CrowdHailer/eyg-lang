package fern

func zipper(source Node, path []int) (Node, func(Node) Node, error) {
	tree := source
	var bs []func(Node) Node
	for _, p := range path {
		t, b, err := tree.child(p)
		tree = t
		if err != nil {
			return Var{}, nil, err
		}
		bs = append(bs, b)
	}
	return tree, func(n Node) Node {
		for i := len(bs) - 1; i >= 0; i-- {
			n = bs[i](n)
		}
		return n
	}, nil
}

// (call, (call, cons, x), tail)
// ((cons x) tail)
// (reverse (uppercase "bob"))
// ((map users) uppercase)

// x -> pre on list
// default is 5 -> [5] but also [1, 2] -> [1, [2]]
// always add to list
