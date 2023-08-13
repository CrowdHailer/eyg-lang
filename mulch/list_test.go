package mulch

import (
	"testing"

	"github.com/tj/assert"
)

func TestList(t *testing.T) {
	e := emptyEnv()
	k := (K)(nil)
	source := &Cons{}
	// defunc, _, _ := source.step(e, k)
	// can't step
	defunc := (C)(source)
	partial, _, _ := defunc.(Value).call(&Integer{1}, e, k)
	list, _, _ := partial.(Value).call(&Tail{}, e, k)
	assert.Nil(t, defunc.(*Cons).item)
	assert.Nil(t, defunc.(*Cons).tail)

	assert.NotNil(t, partial.(*Cons).item)
	assert.Nil(t, partial.(*Cons).tail)

	assert.NotNil(t, list.(*Cons).item)
	assert.NotNil(t, list.(*Cons).tail)
}
