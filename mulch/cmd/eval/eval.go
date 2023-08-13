package main

import (
	"flag"
	"fmt"
	"mulch"
	"os"
)

func main() {
	// Must be called after all flags are defined and before flags are accessed by the program.
	flag.Parse()
	args := flag.Args()

	if len(args) != 1 {
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
	value, fail := mulch.Eval(source, &mulch.Done{})
	if fail != nil {
		fmt.Println(fail.Reason())
		return
	}
	fmt.Println(value.Debug())
}
