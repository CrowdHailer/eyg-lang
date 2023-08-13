package main

import "mulch"

// a = {foo: "string"}
// a.foo

type Extend struct {
	label string
	value any
	rest  any
}
type Empty struct {
}
func (self*Empty)record() (Record, error)  {
	return self, nil
}

func get(value any, label string) {

}
// interface as record
// immutable data structures
// overwrite
// get
// extend

// CPS for effects
// ban handlers means transpile pull out the handler from the top level

func main() {
	a := Extend{"foo", "string", Empty{}}
	// a.get("foo")
	get(a, "foo")

	
	var source mulch.C
	switch exp := source.(type) {
	case *mulch.Select:
		fn(value) {
			value.(*Extend)
		}
	}
}
