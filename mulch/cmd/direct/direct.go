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
	"golang.org/x/exp/maps"
)

func main() {
	flag.Parse()
	args := flag.Args()

	if len(args) < 1 {
		fmt.Println("provide a file to execute")
		return
	}
	file := args[0]
	if len(args) < 2 {
		fmt.Println("provide a package name to execute")
		return
	}
	pkgName := args[1]
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

	counter := 0
	contents, err := printAsFile(transpile(source, &counter, make(map[string]string), true), pkgName, fnName)
	os.WriteFile(out, []byte(contents), 0644)
}

func printAsFile(code []ast.Stmt, pkgName, fnName string) (string, error) {
	buf := new(bytes.Buffer)
	dump := &ast.File{
		Name: &ast.Ident{Name: pkgName},
		Decls: []ast.Decl{
			&ast.GenDecl{Tok: token.IMPORT, Specs: []ast.Spec{
				&ast.ImportSpec{Path: string_("mulch/cmd/direct/core")},
			}},
			&ast.FuncDecl{
				Name: &ast.Ident{Name: fnName},
				Type: &ast.FuncType{Results: &ast.FieldList{List: []*ast.Field{{Type: &ast.Ident{Name: "any"}}}}},
				Body: &ast.BlockStmt{List: code},
			},
		},
	}
	err := printer.Fprint(buf, token.NewFileSet(), dump)
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}

// Needs ssa an this to be passed through
func transpile(exp mulch.C, counter *int, env map[string]string, tail bool) []ast.Stmt {
	switch e := exp.(type) {
	case *mulch.Variable:
		return wrapReturn(AsExpr(e, counter, env), tail)
	case *mulch.Call:
		return wrapReturn(AsExpr(e, counter, env), tail)
	case *mulch.Let:
		i := *counter
		*counter = i + 1
		clone := maps.Clone(env)
		ssa := fmt.Sprintf("%s%d", e.Label, i)
		assign := []ast.Stmt{
			&ast.DeclStmt{Decl: &ast.GenDecl{Tok: token.VAR, Specs: []ast.Spec{
				&ast.ValueSpec{
					Names:  []*ast.Ident{{Name: ssa}},
					Type:   &ast.Ident{Name: "any"},
					Values: []ast.Expr{AsExpr(e.Value, counter, clone)}},
			}}},
			&ast.AssignStmt{
				Lhs: []ast.Expr{&ast.Ident{Name: "_"}},
				Tok: token.ASSIGN,
				Rhs: []ast.Expr{&ast.Ident{Name: ssa}},
			},
		}
		env[e.Label] = ssa
		return append(assign, transpile(e.Then, counter, env, tail)...)
	case *mulch.Integer:
		return wrapReturn(AsExpr(e, counter, env), tail)
	case *mulch.Empty:
		return wrapReturn(AsExpr(e, counter, env), tail)
	}
	fmt.Printf("%#v\n", exp)
	panic("unknown statement")
}

func AsExpr(exp mulch.C, counter *int, env map[string]string) ast.Expr {
	switch e := exp.(type) {
	case *mulch.Variable:
		ssa, ok := env[e.Label]
		if !ok {
			panic("need my variable")
		}
		return &ast.Ident{Name: ssa}
	case *mulch.Let:
		return &ast.CallExpr{
			Fun: &ast.FuncLit{
				Type: &ast.FuncType{Results: &ast.FieldList{List: []*ast.Field{{Type: &ast.Ident{Name: "any"}}}}},
				Body: &ast.BlockStmt{List: transpile(e, counter, env, true)},
			},
		}
	case *mulch.Lambda:
		i := *counter
		*counter = i + 1
		ssa := fmt.Sprintf("%s%d", e.Label, i)
		clone := maps.Clone(env)
		clone[e.Label] = ssa
		return &ast.FuncLit{
			Type: &ast.FuncType{
				Params: &ast.FieldList{List: []*ast.Field{
					{Names: []*ast.Ident{{Name: ssa}}, Type: &ast.Ident{Name: "any"}},
				}},
				Results: &ast.FieldList{List: []*ast.Field{{Type: &ast.Ident{Name: "any"}}}},
			},
			Body: &ast.BlockStmt{List: transpile(e.Body, counter, clone, true)},
		}
	case *mulch.Call:
		cast := &ast.TypeAssertExpr{X: AsExpr(e.Fn, counter, env), Type: &ast.FuncType{
			Params:  &ast.FieldList{List: []*ast.Field{{Type: &ast.Ident{Name: "any"}}}},
			Results: &ast.FieldList{List: []*ast.Field{{Type: &ast.Ident{Name: "any"}}}},
		}}
		return &ast.CallExpr{Fun: cast, Args: []ast.Expr{AsExpr(e.Arg, counter, env)}}
	case *mulch.Integer:
		return integer_(int(e.Value))
	case *mulch.String:
		return string_(e.Value)
	case *mulch.Empty:
		return &ast.CallExpr{Fun: coreFn("Empty"), Args: []ast.Expr{}}
	case *mulch.Tag:
		return &ast.CallExpr{Fun: coreFn("Tag"), Args: []ast.Expr{&ast.Ident{Name: quoteString(e.Label)}}}
	case *mulch.Perform:
		return &ast.CallExpr{Fun: &ast.Ident{Name: "__perform"}, Args: []ast.Expr{&ast.Ident{Name: quoteString(e.Label)}}}
	}

	fmt.Printf("%#v\n", exp)
	panic("unknown expression")
}

func integer_(v int) *ast.BasicLit {
	return &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(v)}
}
func string_(v string) *ast.BasicLit {
	return &ast.BasicLit{Kind: token.STRING, Value: quoteString(v)}
}

func coreFn(f string) *ast.SelectorExpr {
	return &ast.SelectorExpr{X: &ast.Ident{Name: "core"}, Sel: &ast.Ident{Name: f}}
}
func quoteString(v string) string {
	return fmt.Sprintf("\"%s\"", v)
}

func wrapReturn(exp ast.Expr, tail bool) []ast.Stmt {
	if !tail {
		return []ast.Stmt{&ast.ExprStmt{X: exp}}
	}
	return []ast.Stmt{&ast.ReturnStmt{Results: []ast.Expr{exp}}}
}
