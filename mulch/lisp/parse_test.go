package lisp_test

import (
	"mulch"
	"mulch/lisp"
	"testing"

	"github.com/tj/assert"
)

func TestParseLiterals(t *testing.T) {
	assert.Equal(t, &mulch.Integer{Value: 123}, lisp.Parse("123"))
	assert.Equal(t, &mulch.String{Value: "abc"}, lisp.Parse("\"abc\""))
	// square brackets for lists
	assert.Equal(t, &mulch.Variable{Label: "x"}, lisp.Parse("x"))
}

func TestFunctionCalls(t *testing.T) {
	expected := &mulch.Call{
		Fn: &mulch.Call{
			Fn:  &mulch.Variable{Label: "foo"},
			Arg: &mulch.Variable{Label: "a"},
		},
		Arg: &mulch.Integer{Value: 1},
	}
	assert.Equal(t, expected, lisp.Parse("(foo a 1)"))
	expected = &mulch.Call{
		Fn: &mulch.Variable{Label: "foo"},
		Arg: &mulch.Call{
			Fn:  &mulch.Variable{Label: "x"},
			Arg: &mulch.Integer{Value: 1},
		},
	}
	assert.Equal(t, expected, lisp.Parse("(foo (x 1))"))
	expected = &mulch.Call{
		Fn: &mulch.Call{
			Fn: &mulch.Variable{Label: "foo"},

			Arg: &mulch.Call{
				Fn:  &mulch.Variable{Label: "x"},
				Arg: &mulch.Integer{Value: 1},
			},
		},

		Arg: &mulch.Integer{Value: 2},
	}
	assert.Equal(t, expected, lisp.Parse("(foo (x 1) 2)"))
}

func TestUnit(t *testing.T) {
	assert.Equal(t, &mulch.Empty{}, lisp.Parse("()"))
}

func TestList(t *testing.T) {
	var expected mulch.C = &mulch.Tail{}
	assert.Equal(t, expected, lisp.Parse("[]"))

	expected = &mulch.Call{
		Fn: &mulch.Call{
			Fn:  &mulch.Cons{},
			Arg: &mulch.Integer{Value: 1},
		},
		Arg: &mulch.Call{
			Fn: &mulch.Call{
				Fn:  &mulch.Cons{},
				Arg: &mulch.Integer{Value: 2},
			},
			Arg: &mulch.Tail{},
		},
	}

	// no commas
	assert.Equal(t, expected, lisp.Parse("[1 2]"))
}

func TestSelect(t *testing.T) {
	expected := &mulch.Call{Fn: &mulch.Select{Label: "foo"}, Arg: &mulch.Variable{Label: "x"}}
	assert.Equal(t, expected, lisp.Parse("x.foo"))
}
