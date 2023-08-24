package main

import (
	"mulch/cmd/transpile/generated"
	"testing"

	"github.com/tj/assert"
)

func TestNestedLet(t *testing.T) {
	var result any
	generated.NestedLet(func(v any) { result = v })
	assert.Equal(t, 1, result)
}
