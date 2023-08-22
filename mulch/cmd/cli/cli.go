package main

import (
	"flag"
	"fmt"
	"mulch"
	"os"

	"golang.org/x/exp/slices"
)

// go run ./cmd/cli ../eyg/saved/saved.json fetch
func main() {
	// Must be called after all flags are defined and before flags are accessed by the program.
	flag.Parse()
	args := flag.Args()

	if len(args) < 1 {
		fmt.Println("provide a file to execute")
		return
	}
	file := args[0]
	json, err := os.ReadFile(file)
	if err != nil {
		fmt.Printf("error reading file '%s' \n", file)
		return
	}
	source, err := mulch.Decode(json)
	if err != nil {
		fmt.Printf("error decoding program source from '%s' \n", file)
		return
	}
	args = args[1:]
	slices.Reverse(args)
	var list mulch.Value = &mulch.Tail{}
	for _, a := range args {
		list = &mulch.Cons{Item: &mulch.String{Value: a}, Tail: list}
	}

	value, fail := mulch.Eval(source, &mulch.Stack{
		K: &mulch.Apply{Fn: &mulch.Select{Label: "cli"}, Env: nil},
		Rest: &mulch.Stack{
			K:    &mulch.CallWith{Value: list},
			Rest: &mulch.Done{External: mulch.Standard},
		},
	})
	if fail != nil {
		fmt.Println(fail.Reason())
		return
	}
	fmt.Println(value.Debug())
}
