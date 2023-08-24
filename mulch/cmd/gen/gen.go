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
	constant := print(source)
	contents := fmt.Sprintf("package main\nimport \"mulch\"\nvar source = %s", constant)
	os.WriteFile("source.go", []byte(contents), 0644)
}

func print(source mulch.C) string {
	switch exp := source.(type) {
	case *mulch.Variable:
		return fmt.Sprintf("&mulch.Variable{\"%s\"}", exp.Label)
	case *mulch.Lambda:
		return fmt.Sprintf("&mulch.Lambda{\"%s\", %s}", exp.Label, print(exp.Body))
	case *mulch.Call:
		return fmt.Sprintf("&mulch.Call{%s, %s}", print(exp.Fn), print(exp.Arg))
	case *mulch.Let:
		return fmt.Sprintf("&mulch.Let{\"%s\", %s, %s}", exp.Label, print(exp.Value), print(exp.Then))
	case *mulch.String:
		return fmt.Sprintf("&mulch.String{\"%s\"}", exp.Value)
	case *mulch.Perform:
		return fmt.Sprintf("&mulch.Perform{\"%s\"}", exp.Label)
	}
	fmt.Printf("unknown expression %#v", source)
	panic("unknown expression")
}
