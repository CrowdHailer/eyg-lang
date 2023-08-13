package main

import (
	"fmt"
	"mulch"
)

//go:generate go run ../gen/gen.go ../../../website/public/db/hello.json

func main() {
	value, fail := mulch.Eval(source, &mulch.Done{External: map[string]func(mulch.Value) mulch.C{}})
	if fail != nil {
		fmt.Println(fail.Reason())
		return
	}
	fmt.Println(value.Debug())
}
