package main

import (
	"fmt"
	"os"
	"testing"

	"github.com/tj/assert"
)

func TestStandardPrograms(t *testing.T) {
	tests := []struct {
		name       string
		sourceFile string
		want       Value
	}{
		{
			name:       "environment capture",
			sourceFile: "./test/environment_capture.json",
			want:       &Integer{1},
		},
		{
			name:       "parameter added to environment",
			sourceFile: "./test/param_in_env.json",
			want:       &Integer{2},
		},
		{
			name:       "nested apply",
			sourceFile: "./test/nested_apply.json",
			want:       &Integer{4},
		},
		{
			name:       "nested let",
			sourceFile: "./test/nested_let.json",
			want:       &Integer{1},
		},
		{
			name:       "evaluate exec function",
			sourceFile: "./test/effects/evaluate_exec_function.json",
			want:       &Tag{"Ok", &Integer{5}},
		},
		{
			name:       "evaluate handle",
			sourceFile: "./test/effects/evaluate_handle.json",
			want:       &Tag{"Error", &String{"bang!!"}},
		},
		{
			name:       "continue exec",
			sourceFile: "./test/effects/continue_exec.json",
			want:       &Tag{"Tagged", &Integer{1}},
		},
		{
			name:       "multiple perform",
			sourceFile: "./test/effects/multiple_perform.json",
			want:       &Cons{&Integer{1}, &Cons{&Integer{2}, &Tail{}}},
		},
		{
			name:       "multiple resume",
			sourceFile: "./test/effects/multiple_resume.json",
			want:       &Cons{&Integer{2}, &Cons{&Integer{3}, &Tail{}}},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			source := readSource(t, tt.sourceFile)
			got, err := eval(source, &Done{})
			if err != nil {
				fmt.Println(err.reason.debug())
			}
			assert.Nil(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func readSource(t *testing.T, sourceFile string) C {
	json, err := os.ReadFile(sourceFile)
	if err != nil {
		t.Fatal(err)
	}
	source, err := decode(json)
	if err != nil {
		t.Fatal(err)
	}
	return source
}
