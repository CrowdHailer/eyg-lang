package main

import (
	"fmt"
	"os"
	"testing"

	"github.com/tj/assert"
)

// Infer test is the Records example
func TestInfer(t *testing.T) {
	// json, err := os.ReadFile("../website/public/db/infer.json")
	json, err := os.ReadFile("../eyg/saved/saved.json")
	assert.NoError(t, err)
	source, err := decode(json)
	assert.NoError(t, err)

	value, fail := eval(source, &Stack{&Apply{&Select{"cli"}, emptyEnv()}, &Stack{&CallWith{&Cons{&String{"test"}, &Tail{}}}, &Done{}}})
	if value != nil {
		fmt.Printf("Value %#v\n", value.debug())
	}
	if fail != nil {
		fmt.Printf("FAIL %#v\n", fail.reason.debug())
	}
	assert.Nil(t, fail)
	assert.Equal(t, &Integer{0}, value)
}
