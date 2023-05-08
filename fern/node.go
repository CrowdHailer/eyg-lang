package fern

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
)

type Node interface {
	// could return list of strings
	Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool)
	child(int) (Node, func(Node) Node, error)
}

type Fn struct {
	param string
	body  Node
}

var _ Node = Fn{}

// is there a way to make this all on the grid for lookup
// Is there a node then continuation version of this draw
func (fn Fn) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	WriteString(s, fn.param, writer, grid, path, g2, self)
	WriteString(s, " -> ", writer, grid, path, g2, self)
	fn.body.Draw(s, writer, grid, append(path, 0), g2, index, indent, true)
}

func (fn Fn) child(c int) (Node, func(Node) Node, error) {
	if c == 0 {
		return fn.body, func(n Node) Node { return Fn{fn.param, n} }, nil
	}
	return Var{}, nil, fmt.Errorf("invalid child id for fn %d", c)
}

// TODO How do I test
// TODO update grid
// func dummyGrid(g [][]int) {
// 	g[0][5] = 1
// }

type Call struct {
	fn  Node
	arg Node
}

var _ Node = Call{}

// Only the brackets are the actual call node
func (call Call) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	switch inner := call.fn.(type) {
	case Call:
		switch inner.fn.(type) {
		case Cons:
			WriteString(s, "[", writer, grid, path, g2, self)
			// second call
			*index++
			// cons
			*index++
			next := *index
			inner.arg.Draw(s, writer, grid, append(path, 0, 1), g2, index, indent, true)
			// label block as true?
			// turning x into tail makes no difference in cursor for , and value
			// , comma points to first in pair of applies
			// NO BECAUSE it's nested to 0,1 for value but commas are the apply thing
			// making one element list special case that doesn't show up often
			// child could draw comma is it's self at this point
			// Render comma in the print list view.
			WriteString(s, ", ", writer, grid, append(path, 1), g2, next)
			call.arg.Draw(s, writer, grid, append(path, 1), g2, index, indent, true)
			WriteString(s, "]", writer, grid, path, g2, self)
			// Everything is a block (record, case, etc) cursor should keep track of last block
			// Certain key commands should add in block
			return
		}
	}
	call.fn.Draw(s, writer, grid, append(path, 0), g2, index, indent, true)
	WriteString(s, "(", writer, grid, path, g2, self)
	call.arg.Draw(s, writer, grid, append(path, 1), g2, index, indent, true)
	WriteString(s, ")", writer, grid, path, g2, self)
}

func (call Call) child(c int) (Node, func(Node) Node, error) {
	if c == 0 {
		return call.fn, func(n Node) Node { return Call{n, call.arg} }, nil
	}
	if c == 1 {
		return call.arg, func(n Node) Node { return Call{call.fn, n} }, nil
	}
	return Var{}, nil, fmt.Errorf("invalid child id for call %d", c)
}

type Var struct {
	label string
}

var _ Node = Var{}

func (var_ Var) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	WriteString(s, var_.label, writer, grid, path, g2, self)
}
func (var_ Var) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Var %d", c)
}

type Let struct {
	label string
	value Node
	then  Node
}

var _ Node = Let{}

func (let Let) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	// ++ only once a node
	if block {
		WriteString(s, "{", writer, grid, path, g2, self)
		indent += 2
		writer.Y += 1
		writer.X = indent
		defer func() {
			writer.Y += 1
			writer.X = indent - 2
			WriteString(s, "}", writer, grid, path, g2, self)
		}()
	}
	WriteString(s, "let ", writer, grid, path, g2, self)
	WriteString(s, let.label, writer, grid, path, g2, self)
	WriteString(s, " = ", writer, grid, path, g2, self)
	let.value.Draw(s, writer, grid, append(path, 0), g2, index, indent, true)
	writer.Y += 1
	writer.X = indent
	let.then.Draw(s, writer, grid, append(path, 1), g2, index, indent, true)
}

func (let Let) child(c int) (Node, func(Node) Node, error) {
	if c == 0 {
		return let.value, func(n Node) Node { return Let{let.label, n, let.then} }, nil
	}
	if c == 1 {
		return let.then, func(n Node) Node { return Let{let.label, let.value, n} }, nil
	}
	return Var{}, nil, fmt.Errorf("invalid child id for Let %d", c)
}

type Integer struct {
	value int
}

var _ Node = Integer{}

func (i Integer) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("%d", i.value), writer, grid, path, g2, self)
}

func (Integer) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Integer %d", c)
}

type String struct {
	value string
}

var _ Node = String{}

func (str String) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	WriteString(s, "\"", writer, grid, path, g2, self)
	WriteString(s, str.value, writer, grid, path, g2, self)
	WriteString(s, "\"", writer, grid, path, g2, self)
}

func (String) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for String %d", c)
}

type Tail struct {
}

var _ Node = Tail{}

func (Tail) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	WriteString(s, "[]", writer, grid, path, g2, self)
}

func (Tail) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Tail %d", c)
}

type Cons struct {
}

var _ Node = Cons{}

func (Cons) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	self := *index
	*index++
	WriteString(s, "cons", writer, grid, path, g2, self)
}

func (Cons) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Tail %d", c)
}

func WriteString(s tcell.Screen, content string, writer *Point, grid *[][][]int, path []int, g2 *[][]int, id int) {
	for _, ch := range content {
		s.SetContent(writer.X, writer.Y, ch, nil, tcell.StyleDefault)
		(*grid)[writer.X][writer.Y] = path
		(*g2)[writer.X][writer.Y] = id
		writer.X++
	}
}
