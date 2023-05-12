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

// making my own gc
// fast list of parents possible
// func z(source []string, remaining int) {
// 	root := source[0]
// }

// func unwrap(source []string, at int) {
// 	var parents = []string{}
// 	parent = parents[at]
// 	i := 0
// 	new := []string{}
// 	for i := 0; i < parent; i++ {
// 		new = append(new, source[i])
// 	}
// 	for i := at; i < len(source); i++ {
// 		new = append(new, source[i])
// 	}
// 	return new[12]
// }

// func callWith(source []string, at int) [2]int {
// 	// can have arrays for performance
// 	new := []string{}
// 	for i := 0; i < at; i++ {
// 		new = append(new, source[i])
// 	}
// 	new = append(new, "call", "vacant")
// 	for i := at; i < len(source); i++ {
// 		new = append(new, source[i])
// 	}

// }
