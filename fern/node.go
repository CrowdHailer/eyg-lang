package fern

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
)

type Node interface {
	// could return list of strings
	Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool)
}

type Fn struct {
	param string
	body  Node
}

var _ Node = Fn{}

// is there a way to make this all on the grid for lookup
// Is there a node then continuation version of this draw
func (fn Fn) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	WriteString(s, fn.param, writer, grid, path, g2, index)
	WriteString(s, " -> ", writer, grid, path, g2, index)
	fn.body.Draw(s, writer, grid, append(path, 0), g2, index, indent, true)
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
	call.fn.Draw(s, writer, grid, append(path, 0), g2, index, indent, true)
	WriteString(s, "(", writer, grid, path, g2, index)
	call.arg.Draw(s, writer, grid, append(path, 1), g2, index, indent, true)
	WriteString(s, ")", writer, grid, path, g2, index)
}

type Var struct {
	label string
}

var _ Node = Var{}

func (var_ Var) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	WriteString(s, var_.label, writer, grid, path, g2, index)
}

type Let struct {
	label string
	value Node
	then  Node
}

var _ Node = Let{}

func (let Let) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	if block {
		WriteString(s, "{", writer, grid, path, g2, index)
		indent += 2
		writer.Y += 1
		writer.X = indent
		defer func() {
			writer.Y += 1
			writer.X = indent - 2
			WriteString(s, "}", writer, grid, path, g2, index)
		}()
	}
	WriteString(s, "let ", writer, grid, path, g2, index)
	WriteString(s, let.label, writer, grid, path, g2, index)
	WriteString(s, " = ", writer, grid, path, g2, index)
	*index++
	let.value.Draw(s, writer, grid, append(path, 0), g2, index, indent, true)
	writer.Y += 1
	writer.X = indent
	*index++
	let.then.Draw(s, writer, grid, append(path, 1), g2, index, indent, true)
}

type Integer struct {
	value int
}

var _ Node = Integer{}

func (i Integer) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	WriteString(s, fmt.Sprintf("%d", i.value), writer, grid, path, g2, index)
}

type String struct {
	value string
}

var _ Node = String{}

func (str String) Draw(s tcell.Screen, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int, indent int, block bool) {
	WriteString(s, "\"", writer, grid, path, g2, index)
	WriteString(s, str.value, writer, grid, path, g2, index)
	WriteString(s, "\"", writer, grid, path, g2, index)
}

func WriteString(s tcell.Screen, content string, writer *Point, grid *[][][]int, path []int, g2 *[][]int, index *int) {
	for _, ch := range content {
		s.SetContent(writer.X, writer.Y, ch, nil, tcell.StyleDefault)
		(*grid)[writer.X][writer.Y] = path
		(*g2)[writer.X][writer.Y] = *index
		writer.X++
	}
}
