package mulch

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
	source, err := Decode(json)
	assert.NoError(t, err)

	// No exposed cli field, use only exec
	// value, fail := Eval(source, &Stack{&Apply{&Select{"cli"}, emptyEnv()}, &Stack{&CallWith{&Cons{&String{"test"}, &Tail{}}}, &Done{Standard}}})
	value, fail := Eval(source, &Done{Standard})
	if value != nil {
		fmt.Printf("Value %#v\n", value.Debug())
	}
	if fail != nil {
		fmt.Printf("FAIL %#v\n", fail.R.debug())
	}
	assert.Nil(t, fail)
	// assert.Equal(t, &Integer{0}, value)
}
