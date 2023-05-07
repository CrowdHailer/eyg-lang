package fern

func Source() Node {
	return Let{"x", Let{"a", String{"hello world!"}, Call{Call{Var{"x"}, Integer{5}}, Integer{5}}}, Var{"x"}}
	// return Call{Var{"x"}, Var{"y"}}
}
