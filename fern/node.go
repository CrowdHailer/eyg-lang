package fern

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
)

type Node interface {
	// could return list of strings
	draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool)
	child(int) (Node, func(Node) Node, error)
}

type Fn struct {
	param string
	body  Node
}

var _ Node = Fn{}

// is there a way to make this all on the grid for lookup
// Is there a node then continuation version of this draw
func (fn Fn) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fn.param, writer, grid, path, g2, self, tcell.StyleDefault)
	WriteString(s, " -> ", writer, grid, path, g2, self, tcell.StyleDefault)
	fn.body.draw(s, writer, grid, append(path, 0), g2, index, indent, true, false)
}

func (fn Fn) child(c int) (Node, func(Node) Node, error) {
	if c == 0 {
		return fn.body, func(n Node) Node { return Fn{fn.param, n} }, nil
	}
	return Var{}, nil, fmt.Errorf("invalid child id for fn %d", c)
}

type Call struct {
	fn  Node
	arg Node
}

var _ Node = Call{}

// Only the brackets are the actual call node
func (call Call) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	switch inner := call.fn.(type) {
	case Call:
		switch inner.fn.(type) {
		case Cons:
			if !list {
				WriteString(s, "[", writer, grid, path, g2, self, tcell.StyleDefault)
			}
			// second call
			*index++
			// cons
			*index++
			next := *index
			inner.arg.draw(s, writer, grid, append(path, 0, 1), g2, index, indent, true, false)
			// label block as true?
			// turning x into tail makes no difference in cursor for , and value
			// , comma points to first in pair of applies
			// NO BECAUSE it's nested to 0,1 for value but commas are the apply thing
			// making one element list special case that doesn't show up often
			// child could draw comma is it's self at this point
			// Render comma in the print list view.
			WriteString(s, ", ", writer, grid, append(path, 1), g2, next, tcell.StyleDefault)
			call.arg.draw(s, writer, grid, append(path, 1), g2, index, indent, true, true)
			if !list {
				WriteString(s, "]", writer, grid, path, g2, self, tcell.StyleDefault)
			}
			// Everything is a block (record, case, etc) cursor should keep track of last block
			// Certain key commands should add in block
			return
		}
	}
	call.fn.draw(s, writer, grid, append(path, 0), g2, index, indent, true, false)
	WriteString(s, "(", writer, grid, path, g2, self, tcell.StyleDefault)
	call.arg.draw(s, writer, grid, append(path, 1), g2, index, indent, true, false)
	WriteString(s, ")", writer, grid, path, g2, self, tcell.StyleDefault)
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

func (var_ Var) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	if list {
		WriteString(s, "..", writer, grid, path, g2, self, tcell.StyleDefault)
	}
	WriteString(s, var_.label, writer, grid, path, g2, self, tcell.StyleDefault)
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

func (let Let) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	// ++ only once a node
	if list {
		WriteString(s, "..", writer, grid, path, g2, self, tcell.StyleDefault)
	}
	if block {
		WriteString(s, "{", writer, grid, path, g2, self, tcell.StyleDefault)
		indent += 2
		writer.Y += 1
		writer.X = indent
		defer func() {
			writer.Y += 1
			writer.X = indent - 2
			WriteString(s, "}", writer, grid, path, g2, self, tcell.StyleDefault)
		}()
	}
	WriteString(s, "let ", writer, grid, path, g2, self, tcell.StyleDefault.Dim(true))
	WriteString(s, let.label, writer, grid, path, g2, self, tcell.StyleDefault)
	WriteString(s, " = ", writer, grid, path, g2, self, tcell.StyleDefault)
	let.value.draw(s, writer, grid, append(path, 0), g2, index, indent, true, false)
	writer.Y += 1
	writer.X = indent
	let.then.draw(s, writer, grid, append(path, 1), g2, index, indent, true, false)
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

type Vacant struct {
	note string
}

var _ Node = Vacant{}

func (v Vacant) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, v.note, writer, grid, path, g2, self, tcell.StyleDefault.Foreground(tcell.NewHexColor(0xff0000)))
}

func (Vacant) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Vacant %d", c)
}

type Integer struct {
	value int
}

var _ Node = Integer{}

func (i Integer) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("%d", i.value), writer, grid, path, g2, self, tcell.StyleDefault.Foreground(tcell.NewHexColor(0xff00ee)))
}

func (Integer) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Integer %d", c)
}

type String struct {
	value string
}

var _ Node = String{}

func (str String) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	green := tcell.StyleDefault.Foreground(tcell.NewHexColor(0x00ff00))
	WriteString(s, "\"", writer, grid, path, g2, self, green)
	WriteString(s, str.value, writer, grid, path, g2, self, green)
	WriteString(s, "\"", writer, grid, path, g2, self, green)
}

func (String) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for String %d", c)
}

type Tail struct {
}

var _ Node = Tail{}

func (Tail) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	if !list {
		WriteString(s, "[]", writer, grid, path, g2, self, tcell.StyleDefault)
	}
}

func (Tail) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Tail %d", c)
}

type Cons struct {
}

var _ Node = Cons{}

func (Cons) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, "cons", writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Cons) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Tail %d", c)
}

type Empty struct {
}

var _ Node = Empty{}

func (Empty) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, "{}", writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Empty) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Empty %d", c)
}

type Extend struct {
	label string
}

var _ Node = Extend{}

func (e Extend) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("+%s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Extend) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Extend %d", c)
}

type Select struct {
	label string
}

var _ Node = Select{}

func (e Select) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf(".%s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Select) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Select %d", c)
}

type Overwrite struct {
	label string
}

var _ Node = Overwrite{}

func (e Overwrite) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf(":%s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Overwrite) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Overwrite %d", c)
}

type Tag struct {
	label string
}

var _ Node = Tag{}

func (e Tag) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("%s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Tag) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Tag %d", c)
}

type Case struct {
	label string
}

var _ Node = Case{}

func (e Case) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("+%s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Case) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Case %d", c)
}

type NoCases struct {
}

var _ Node = NoCases{}

func (e NoCases) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, "nocases", writer, grid, path, g2, self, tcell.StyleDefault)
}

func (NoCases) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for NoCases %d", c)
}

type perform struct {
	label string
}

var _ Node = perform{}

func (e perform) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("perform %s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (perform) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for perform %d", c)
}

type Handle struct {
	label string
}

var _ Node = Handle{}

func (e Handle) draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool, list bool) {
	self := *index
	*index++
	WriteString(s, fmt.Sprintf("handle %s", e.label), writer, grid, path, g2, self, tcell.StyleDefault)
}

func (Handle) child(c int) (Node, func(Node) Node, error) {
	return Var{}, nil, fmt.Errorf("invalid child id for Handle %d", c)
}

func WriteString(s tcell.Screen, content string, writer *Point, grid *[][][]int, path []int, g2 *[][]int, id int, style tcell.Style) {
	// tcell.StyleDefault.
	for _, ch := range content {
		s.SetContent(writer.X, writer.Y, ch, nil, style)
		(*grid)[writer.X][writer.Y] = path
		(*g2)[writer.X][writer.Y] = id
		writer.X++
	}
}
