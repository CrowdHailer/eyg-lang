package fern

import (
	"encoding/json"
	"fmt"
	"testing"
)

func Test_encoding(t *testing.T) {
	bytes, err := json.Marshal(Fn{"x", String{"bob"}})
	if err != nil {
		t.Fatal(err)
	}
	fmt.Println(string(bytes))
	panic("s")
}
