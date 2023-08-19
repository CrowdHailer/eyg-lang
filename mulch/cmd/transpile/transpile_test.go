package main

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"log"
	"mulch"
	"os"
	"testing"

	"github.com/tj/assert"
)

func TestExample(t *testing.T) {
	var value any
	func(x any) {
		func(x any) {
			value = x
		}(2)
	}(1)
	assert.Equal(t, 2, value)
}

func TestStandardPrograms(t *testing.T) {
	tests := []struct {
		name       string
		sourceFile string
		want       mulch.Value
	}{
		{
			name:       "environment capture",
			sourceFile: "../../test/environment_capture.json",
			want:       &mulch.Integer{1},
		},
		// {
		// 	name:       "parameter added to environment",
		// 	sourceFile: "./test/param_in_env.json",
		// 	want:       &Integer{2},
		// },
		// {
		// 	name:       "nested apply",
		// 	sourceFile: "./test/nested_apply.json",
		// 	want:       &Integer{4},
		// },
		// {
		// 	name:       "nested let",
		// 	sourceFile: "./test/nested_let.json",
		// 	want:       &Integer{1},
		// },
		// {
		// 	name:       "evaluate exec function",
		// 	sourceFile: "./test/effects/evaluate_exec_function.json",
		// 	want:       &Tag{"Ok", &Integer{5}},
		// },
		// {
		// 	name:       "evaluate handle",
		// 	sourceFile: "./test/effects/evaluate_handle.json",
		// 	want:       &Tag{"Error", &String{"bang!!"}},
		// },
		// {
		// 	name:       "continue exec",
		// 	sourceFile: "./test/effects/continue_exec.json",
		// 	want:       &Tag{"Tagged", &Integer{1}},
		// },
		// {
		// 	name:       "multiple perform",
		// 	sourceFile: "./test/effects/multiple_perform.json",
		// 	want:       &Cons{&Integer{1}, &Cons{&Integer{2}, &Tail{}}},
		// },
		// {
		// 	name:       "multiple resume",
		// 	sourceFile: "./test/effects/multiple_resume.json",
		// 	want:       &Cons{&Integer{2}, &Cons{&Integer{3}, &Tail{}}},
		// },
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			source := readSource(t, tt.sourceFile)
			code := transpile(source)
			buf := new(bytes.Buffer)
			dump := &ast.File{
				Name: &ast.Ident{Name: "testdata"},
				Decls: []ast.Decl{
					&ast.FuncDecl{
						Name: &ast.Ident{Name: "bob"},
						Type: &ast.FuncType{},
						Body: &ast.BlockStmt{List: []ast.Stmt{&ast.ExprStmt{X: code}}},
					},
				},
			}
			err := printer.Fprint(buf, token.NewFileSet(), dump)
			if err != nil {
				log.Fatal(err)
			}
			fmt.Println(buf.String())
			panic("rad source")
			got, fail := mulch.Eval(source, &mulch.Done{})
			if fail != nil {
				// fmt.Println(fail.reason.debug())
				t.Fatal(fail)
			}
			assert.Nil(t, fail)
			assert.Equal(t, tt.want, got)
		})
	}
}

func readSource(t *testing.T, sourceFile string) mulch.C {
	json, err := os.ReadFile(sourceFile)
	if err != nil {
		t.Fatal(err)
	}
	source, err := mulch.Decode(json)
	if err != nil {
		t.Fatal(err)
	}
	return source
}

func perform(label string, v any, k func(any) any) {
	panic("perform")
}

func doSelect(v, k any) {

}

// I previously had a bunch of nested ks

// func extend(label string, value any, record any, k func(any) any) any {
// 	return k()
// }

// // flatten as go generator i.e define an observable
// // observable machinery just makes it look nice we want oposite for compilation
// // have only one
// //
// //	fn(x){
// //	  let y = perform Foo(x)
// //	  perform Foo(y)
// //	}
// //
// // Do I want to compile functions to functions
// // relying on the type system is best
// // but untyped allows more freedom
// func eval(any) {

// }
// func main() any {
// 	var result any
// 	eval(func(v any) { result = v })
// 	return result
// }

// func example() {
// 	// formating function definiton

// 	perform("Foo").call()

// 	func(x any) {
// 		perform("Foo", x, func(y any) {
// 			perform("Foo", y, func(r any) { return r })
// 		})
// 	}(2)
// }

// func TestTranspile(t *testing.T) {
// 	// var d ast.Expr
// 	buf := new(bytes.Buffer)
// 	err := printer.Fprint(buf, token.NewFileSet(), &ast.FuncLit{
// 		Type: &ast.FuncType{Params: &ast.FieldList{}},
// 		Body: &ast.BlockStmt{List: []ast.Stmt{
// 			// &ast.DeclStmt{Decl: }
// 			&ast.AssignStmt{
// 				Lhs: []ast.Expr{&ast.Ident{Name: "foo"}},
// 				Tok: token.DEFINE,
// 				Rhs: []ast.Expr{&ast.BasicLit{Kind: token.INT, Value: "asc"}},
// 			},
// 			// &ast.BasicLit{Kind: token.INT, Value: "asc"},
// 			&ast.ReturnStmt{Results: []ast.Expr{&ast.Ident{Name: "foo"}}},
// 		}}})
// 	if err != nil {
// 		log.Fatal(err)
// 	}
// 	fmt.Println(buf.String())
// 	panic("todoo tanspuile")
// }
