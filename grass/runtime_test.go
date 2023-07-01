package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestDirectPrimitives(t *testing.T) {
	source := &Term{&Integer{2}}
	result, err := Run(source)
	assert.Nil(t, err)
	assert.Equal(t, &Integer{2}, result)
}

func TestLet(t *testing.T) {
	source := &Let{"x", &Term{&Integer{2}}, &Variable{"x"}}
	result, err := Run(source)
	assert.Nil(t, err)
	assert.Equal(t, &Integer{2}, result)
}

func TestFn(t *testing.T) {
	source := &Call{&Lambda{"x", &Variable{"x"}}, &Term{&Integer{2}}}
	result, err := Run(source)
	assert.Nil(t, err)
	assert.Equal(t, &Integer{2}, result)
}
