package main

import (
	"mulch"
	"testing"

	"github.com/tj/assert"
)

func TestParseLiterals(t *testing.T) {
	assert.Equal(t, &mulch.Integer{Value: 123}, parse("123"))
	assert.Equal(t, &mulch.String{Value: "abc"}, parse("\"abc\""))
	// square brackets for lists
	assert.Equal(t, &mulch.Variable{Label: "x"}, parse("x"))
}

func TestFunctionCalls(t *testing.T) {
	expected := &mulch.Call{
		Fn: &mulch.Call{
			Fn:  &mulch.Variable{Label: "foo"},
			Arg: &mulch.Variable{Label: "a"},
		},
		Arg: &mulch.Integer{Value: 1},
	}
	assert.Equal(t, expected, parse("(foo a 1)"))
	expected = &mulch.Call{
		Fn: &mulch.Variable{Label: "foo"},
		Arg: &mulch.Call{
			Fn:  &mulch.Variable{Label: "x"},
			Arg: &mulch.Integer{Value: 1},
		},
	}
	assert.Equal(t, expected, parse("(foo (x 1))"))
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
	assert.Equal(t, expected, parse("(foo (x 1) 2)"))
}

func TestUnit(t *testing.T) {
	assert.Equal(t, &mulch.Empty{}, parse("()"))
}
