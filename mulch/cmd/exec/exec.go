package main

import (
	"flag"
	"fmt"
	"mulch"
	"mulch/lisp"
	"os"
	"strings"

	"github.com/chzyer/readline"
	"golang.org/x/exp/slices"
)

// go run ./cmd/cli ../eyg/saved/saved.json fetch
func main() {
	// Must be called after all flags are defined and before flags are accessed by the program.
	flag.Parse()
	args := flag.Args()

	envFile := ".env"
	raw, err := os.ReadFile(envFile)
	if err != nil {
		fmt.Printf("error reading envFile '%s' \n", envFile)
	}
	var env mulch.Record = &mulch.Empty{}
	for _, line := range strings.Split(string(raw), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) < 2 {
			fmt.Printf("invalid env line: %v\n", line)
			continue
		}
		env = env.Extend(parts[0], &mulch.String{Value: parts[1]})
	}

	sourceFile := "../eyg/saved/saved.json"
	json, err := os.ReadFile(sourceFile)
	if err != nil {
		fmt.Printf("error reading file '%s' \n", sourceFile)
		return
	}
	source, err := mulch.Decode(json)
	if err != nil {
		fmt.Printf("error decoding program source from '%s' \n", sourceFile)
		return
	}
	slices.Reverse(args)
	var list mulch.Value = &mulch.Tail{}
	for _, a := range args {
		list = &mulch.Cons{Item: &mulch.String{Value: a}, Tail: list}
	}

	exterior := mulch.Standard
	exterior["Env"] = func(v mulch.Value) mulch.C {
		return env
	}
	shell, err := Start(source, list, exterior)
	if err != nil {
		fmt.Printf("failed to start shell: %s\n", err.Error())
		return
	}
	rl, err := readline.New("> ")
	if err != nil {
		fmt.Printf("failed to read input: %s\n", err.Error())
		return
	}
	defer rl.Close()
	for {
		fmt.Print("> ")
		input, err := rl.Readline()
		if err != nil { // io.EOF
			break
		}
		source, err := lisp.Parse(input)
		if err != nil {
			fmt.Printf("failed to parse input: %s\n", err.Error())
			continue
		}
		value, fail := shell.Continue(source)
		if fail != nil {
			// fmt.Printf("%#v %#v\n", value, fail)
			fmt.Println(fail.Reason())
			continue
		}
		fmt.Println(value.Debug())
	}
}

type Shell struct {
	e mulch.E
	k mulch.K
}

func Start(source mulch.C, list mulch.Value, exterior map[string]func(mulch.Value) mulch.C) (*Shell, error) {
	value, fail, e, _ := mulch.EvalResumable(source, &mulch.Stack{
		K: &mulch.Apply{Fn: &mulch.Select{Label: "exec"}, Env: nil},
		Rest: &mulch.Stack{
			K:    &mulch.CallWith{Value: list},
			Rest: &mulch.Done{External: exterior},
		},
	})
	if fail == nil {
		return nil, fmt.Errorf("did not reach a prompt value=%s", value.Debug())
	}
	if _, ok := fail.R.(*mulch.UnhandledEffect); !ok {
		fmt.Printf("%#v\n", value)
		return nil, fmt.Errorf("error reason=%s", fail.Reason())
	}
	if eff, ok := fail.R.(*mulch.UnhandledEffect); ok && eff.Label != "Prompt" {
		fmt.Printf("%#v\n", value)
		return nil, fmt.Errorf("unhandled effect label=%s lift=%s", eff.Label, eff.Lift.Debug())
	}
	return &Shell{e: e, k: &mulch.Done{External: mulch.Standard}}, nil
}

func (shell *Shell) Continue(source mulch.C) (mulch.Value, *mulch.Error) {
	value, fail, e, _ := mulch.ContinueEval(source, shell.e, shell.k)
	// only update e if no error otherwise will get a deep end.
	// should probably map list to prompt
	if _, ok := source.(*mulch.Let); ok && fail == nil {
		shell.e = e
	}
	return value, fail
}

// https://github.com/golang/go/issues/15108
// go to build go
