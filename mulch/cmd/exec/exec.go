package main

import (
	"bufio"
	"flag"
	"fmt"
	"mulch"
	"mulch/lisp"
	"os"

	"golang.org/x/exp/slices"
)

// go run ./cmd/cli ../eyg/saved/saved.json fetch
func main() {
	// Must be called after all flags are defined and before flags are accessed by the program.
	flag.Parse()
	args := flag.Args()

	file := "../eyg/saved/saved.json"
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
	slices.Reverse(args)
	var list mulch.Value = &mulch.Tail{}
	for _, a := range args {
		list = &mulch.Cons{Item: &mulch.String{Value: a}, Tail: list}
	}

	value, fail, e, k := mulch.EvalResumable(source, &mulch.Stack{
		K: &mulch.Apply{Fn: &mulch.Select{Label: "exec"}, Env: nil},
		Rest: &mulch.Stack{
			K:    &mulch.CallWith{Value: list},
			Rest: &mulch.Done{External: mulch.Standard},
		},
	})
	if fail != nil {
		if r, ok := fail.R.(*mulch.UnhandledEffect); ok && r.Label == "Prompt" {
			// source := lisp.Parse(input)
			// fmt.Printf("%#v %#v\n", e, k)
			// panic("Will continue")
			in := bufio.NewReader(os.Stdin)
			input := ""

			// var e E = emptyEnv()
			for input != "." {
				fmt.Print("> ")
				input, err := in.ReadString('\n')
				if err != nil {
					panic(err)
				}
				source, err := lisp.Parse(input)
				if err != nil {
					fmt.Printf("failed to parse input: %s\n", err.Error())
					continue
				}
				// var k = &mulch.Done{}
				// Pass in script value for scripting
				// save program state as script
				value, fail, e, k = mulch.ContinueEval(source, e, k)
				if fail != nil {
					fmt.Println(fail.Reason())
					continue
				}
				fmt.Println(value.Debug())
			}
		}
		fmt.Printf("failed: %s\n", fail.Reason())
		return
	}
	fmt.Println(value.Debug())
}
