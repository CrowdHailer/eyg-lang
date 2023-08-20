package main

import (
	"bytes"
	"flag"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"mulch"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/iancoleman/strcase"
)

// theres some clever thing with a global stack
// push it and then there will be a pop and run.
// what does nested apply look like
var value = &ast.Ident{Name: "any"}
var ktype = &ast.FuncType{
	Params: &ast.FieldList{List: []*ast.Field{{Type: value}}},
	// Results: &ast.FieldList{List: []*ast.Field{{Type: any}}},
}

// arg counter
// need mapping
// gleam js mapping with use
func end(exp ast.Expr, k ast.Expr) *ast.CallExpr {
	return &ast.CallExpr{Fun: &ast.Ident{Name: "then"}, Args: []ast.Expr{exp, k}}
}
func transpile(exp mulch.C, k ast.Expr) ast.Expr {
	switch e := exp.(type) {
	case *mulch.Variable:
		return end(&ast.Ident{Name: e.Label}, k)
	case *mulch.Lambda:
		return end(&ast.FuncLit{
			Type: &ast.FuncType{
				Params: &ast.FieldList{List: []*ast.Field{
					{Names: []*ast.Ident{{Name: e.Label}}, Type: value},
					{Names: []*ast.Ident{{Name: "_k"}}, Type: &ast.Ident{Name: "K"}},
				}}},
			Body: &ast.BlockStmt{List: []ast.Stmt{
				&ast.ExprStmt{X: transpile(e.Body, &ast.Ident{Name: "_k"})},
			}},
		}, k)
	case *mulch.Call:
		// knormalisation
		return transpile(e.Fn, &ast.FuncLit{
			Type: &ast.FuncType{
				Params: &ast.FieldList{List: []*ast.Field{{Names: []*ast.Ident{{Name: "_fn"}}, Type: value}}},
			},
			Body: &ast.BlockStmt{List: []ast.Stmt{
				&ast.ExprStmt{X: transpile(e.Arg, &ast.FuncLit{
					Type: &ast.FuncType{
						Params: &ast.FieldList{List: []*ast.Field{{Names: []*ast.Ident{{Name: "_arg"}}, Type: value}}},
					},
					Body: &ast.BlockStmt{List: []ast.Stmt{
						&ast.ExprStmt{X: &ast.CallExpr{
							Fun: &ast.TypeAssertExpr{X: &ast.Ident{Name: "_fn"}, Type: &ast.FuncType{
								Params: &ast.FieldList{List: []*ast.Field{
									{Type: value},
									{Type: &ast.Ident{Name: "K"}},
								}},
							}},
							Args: []ast.Expr{
								&ast.Ident{Name: "_arg"},
								k,
							},
						},
						},
					}}})},
			}}})
	case *mulch.Let:
		k2 := &ast.FuncLit{
			Type: &ast.FuncType{Params: &ast.FieldList{List: []*ast.Field{
				{Names: []*ast.Ident{{Name: e.Label}}, Type: &ast.Ident{Name: "any"}},
			}}},
			Body: &ast.BlockStmt{List: []ast.Stmt{
				&ast.ExprStmt{X: transpile(e.Then, k)},
				// &ast.BasicLit{Kind: token.INT, Value: "asc"},
				// &ast.ReturnStmt{Results: []ast.Expr{&ast.Ident{Name: "foo"}}},
			}}}
		return transpile(e.Value, k2)
	case *mulch.Integer:
		return end(integer_(int(e.Value)), k)
	case *mulch.String:
		return end(string_(e.Value), k)
	case *mulch.Empty:
		return end(&ast.CompositeLit{Type: &ast.Ident{Name: "empty"}}, k)
	case *mulch.Builtin:
		return end(&ast.Ident{Name: e.Id}, k)
	}

	fmt.Printf("%#v\n", exp)
	panic("unknown thing")
}

// func function() ast.Expr {

// }
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

func integer_(v int) ast.Expr {
	return &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(v)}
}

func string_(v string) ast.Expr {
	return &ast.BasicLit{Kind: token.STRING, Value: v}
}

func printAsFile(code ast.Expr, fnName string) (string, error) {
	buf := new(bytes.Buffer)
	dump := &ast.File{
		Name: &ast.Ident{Name: "generated"},
		Decls: []ast.Decl{
			// &ast.DeclStmt{
			// 	Decl: &ast.TypeSpec{Name: ast.NewIdent("K"), Assign: token.NoPos, Type: ktype},
			// },
			// &ast.GenDecl{Tok: token.TYPE, Specs: []ast.Spec{

			// 	&ast.TypeSpec{Name: &ast.Ident{Name: "K"}, Assign: token.NoPos, Type: ktype},
			// }},
			&ast.FuncDecl{
				Name: &ast.Ident{Name: fnName},
				Type: &ast.FuncType{
					Params: &ast.FieldList{List: []*ast.Field{{Names: []*ast.Ident{{Name: "_k"}}, Type: &ast.Ident{Name: "K"}}}},
				},
				Body: &ast.BlockStmt{List: []ast.Stmt{&ast.ExprStmt{X: code}}},
			},
			// &ast.FuncDecl{
			// 	Name: &ast.Ident{Name: "then"},
			// 	Type: &ast.FuncType{
			// 		Params: &ast.FieldList{List: []*ast.Field{
			// 			{Names: []*ast.Ident{{Name: "value"}}, Type: value},
			// 			{Names: []*ast.Ident{{Name: "k"}}, Type: &ast.Ident{Name: "K"}},
			// 		}},
			// 	},
			// 	Body: &ast.BlockStmt{List: []ast.Stmt{
			// 		&ast.ExprStmt{X: &ast.CallExpr{Fun: &ast.Ident{Name: "k"}, Args: []ast.Expr{&ast.Ident{Name: "value"}}}},
			// 	}},
			// },
		},
	}
	err := printer.Fprint(buf, token.NewFileSet(), dump)
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}

func main() {
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
	fmt.Printf("%#v\n", source)
	name := strings.TrimSuffix(filepath.Base(file), ".json")
	// fnName := strings.ReplaceAll(name, "_", "")
	fnName := strcase.ToCamel(name)
	out := fmt.Sprintf("%s.go", name)

	contents, err := printAsFile(transpile(source, &ast.Ident{Name: "_k"}), fnName)
	os.WriteFile(out, []byte(contents), 0644)
}

// type Extend struct {
// 	label string
// 	value any
// 	rest  any
// }
// type Empty struct {
// }

// func (self *Empty) record() (Record, error) {
// 	return self, nil
// }

// func get(value any, label string) {

// }

// // interface as record
// // immutable data structures
// // overwrite
// // get
// // extend

// // CPS for effects
// // ban handlers means transpile pull out the handler from the top level
