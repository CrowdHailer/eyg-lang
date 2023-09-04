package main

import (
	"mulch"
	"mulch/lisp"
	"testing"

	"github.com/tj/assert"
)

var testSource mulch.C = &mulch.Call{
	Fn: &mulch.Call{
		Fn: &mulch.Extend{Label: "exec"},
		Arg: &mulch.Lambda{Label: "_", Body: &mulch.Let{
			Label: "foo",
			Value: &mulch.String{Value: "FOO!"},
			Then: &mulch.Call{
				Fn:  &mulch.Perform{Label: "Prompt"},
				Arg: &mulch.String{Value: ">"},
			},
		}},
	},
	Arg: &mulch.Empty{},
}

func start(t *testing.T) *Shell {
	shell, err := Start(testSource, &mulch.Tail{})
	assert.NoError(t, err)
	return shell
}

func enter(t *testing.T, shell *Shell, input string) (mulch.Value, *mulch.Error) {
	source, err := lisp.Parse(input)
	assert.NoError(t, err)
	return shell.Continue(source)
}

func TestCanEnterPrimitiveValues(t *testing.T) {
	shell := start(t)

	value, fail := enter(t, shell, "()")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Empty{}, value)

	value, fail = enter(t, shell, "5")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 5}, value)

	value, fail = enter(t, shell, "(5)")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 5}, value)

	value, fail = enter(t, shell, "\"hello\"")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.String{Value: "hello"}, value)
}

func TestAccessAndOverwriteVariable(t *testing.T) {
	shell := start(t)

	value, fail := enter(t, shell, "foo")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.String{Value: "FOO!"}, value)

	value, fail = enter(t, shell, "(foo)")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.String{Value: "FOO!"}, value)

	value, fail = enter(t, shell, "(let foo 1)")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 1}, value)

	value, fail = enter(t, shell, "foo")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 1}, value)
}

func TestSetAndOverwriteVariable(t *testing.T) {
	shell := start(t)

	value, fail := enter(t, shell, "(let x 3)")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 3}, value)

	value, fail = enter(t, shell, "x")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 3}, value)

	value, fail = enter(t, shell, "(let x 4)")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 4}, value)

	value, fail = enter(t, shell, "x")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Integer{Value: 4}, value)
}

// nested lets and using let value

func TestCanEnterLists(t *testing.T) {
	shell := start(t)

	value, fail := enter(t, shell, "[]")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Tail{}, value)

	value, fail = enter(t, shell, "([])")
	assert.Nil(t, fail)
	assert.Equal(t, &mulch.Tail{}, value)

	value, fail = enter(t, shell, "[1 2]")
	assert.Nil(t, fail)
	assert.Equal(t, mulch.List([]mulch.Value{&mulch.Integer{Value: 1}, &mulch.Integer{Value: 2}}), value)
}
