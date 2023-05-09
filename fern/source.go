package fern

func Source() Node {
	// return Let{"x", Let{"a", String{"hello world!"}, Call{Call{Var{"x"}, Integer{5}}, Integer{5}}}, Var{"x"}}
	// return Call{Var{"x"}, Var{"y"}}
	// return Call{Call{Cons{}, Integer{5}}, Call{Call{Cons{}, Integer{61}}, Let{"x", Integer{5}, Tail{}}}}
	return Call{Call{Extend{"foo"}, Integer{10}}, Empty{}}
}

// If there is no increase selection then no getting stuck on not real values
// [a, b, c, |]
// makes thing go to tail if on brackets as top call
// [a, ]
// ^ -> [hole, a, ]
