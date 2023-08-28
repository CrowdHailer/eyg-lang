package lisp_test

import (
	"mulch"
	"mulch/lisp"
	"testing"

	"github.com/tj/assert"
)

func TestParseLiterals(t *testing.T) {
	exp, err := lisp.Parse("123")
	assert.NoError(t, err)
	assert.Equal(t, &mulch.Integer{Value: 123}, exp)

	exp, err = lisp.Parse("\"abc\"")
	assert.NoError(t, err)
	assert.Equal(t, &mulch.String{Value: "abc"}, exp)

	exp, err = lisp.Parse("x")
	assert.NoError(t, err)
	assert.Equal(t, &mulch.Variable{Label: "x"}, exp)
}

func TestFunctionCalls(t *testing.T) {
	expected := &mulch.Call{
		Fn: &mulch.Call{
			Fn:  &mulch.Variable{Label: "foo"},
			Arg: &mulch.Variable{Label: "a"},
		},
		Arg: &mulch.Integer{Value: 1},
	}
	exp, err := lisp.Parse("(foo a 1)")
	assert.NoError(t, err)
	assert.Equal(t, expected, exp)

	expected = &mulch.Call{
		Fn: &mulch.Variable{Label: "foo"},
		Arg: &mulch.Call{
			Fn:  &mulch.Variable{Label: "x"},
			Arg: &mulch.Integer{Value: 1},
		},
	}
	exp, err = lisp.Parse("(foo (x 1))")
	assert.NoError(t, err)
	assert.Equal(t, expected, exp)

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
	exp, err = lisp.Parse("(foo (x 1) 2)")
	assert.NoError(t, err)
	assert.Equal(t, expected, exp)
}

func TestUnit(t *testing.T) {
	exp, err := lisp.Parse("()")
	assert.NoError(t, err)
	assert.Equal(t, &mulch.Empty{}, exp)
}

func TestList(t *testing.T) {
	var expected mulch.C = &mulch.Tail{}
	exp, err := lisp.Parse("[]")
	assert.NoError(t, err)
	assert.Equal(t, expected, exp)

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
	exp, err = lisp.Parse("[1 2]")
	assert.NoError(t, err)
	assert.Equal(t, expected, exp)
}

func TestSelect(t *testing.T) {
	expected := &mulch.Call{Fn: &mulch.Select{Label: "foo"}, Arg: &mulch.Variable{Label: "x"}}
	exp, err := lisp.Parse("x.foo")
	assert.NoError(t, err)
	assert.Equal(t, expected, exp)
}
