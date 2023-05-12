package fern

import (
	"fmt"
	"testing"
)

type Expression interface {
}

// type Fn_ struct {
// 	param string
// }
// type Call_ struct {
// }
// type Var_ struct {
// 	label string
// }
// type Let_ struct {
// 	label string
// }
// type Vacant_ struct {
// }
// type Integer_ struct {
// 	value int
// }
// type String_ struct {
// 	value string
// }

// render
// in e2
// type situ_ struct {
// 	block  bool
// 	nested bool
// 	indent int
// }

func (node String) print(buffer *[]rendered, info map[string]int, situ situ) {
	*buffer = append(*buffer, rendered{charachter: '"', path: situ.path, offset: -1})
	// start of active
	info[pathToString(situ.path)] = len(*buffer)
	for i, ch := range node.value {
		*buffer = append(*buffer, rendered{charachter: ch, offset: i})
	}
	*buffer = append(*buffer, rendered{charachter: '"', path: situ.path, offset: len(node.value)})
	if !situ.nested {
		*buffer = append(*buffer, rendered{charachter: '\n', path: situ.path, offset: -1})
	}
}

func pathToString(path []int) string {
	out := "["
	for i, p := range path {
		if i != 0 {
			out += ","
		}
		out += fmt.Sprintf("%d", p)
	}
	return out + "]"
}

func Print(node String) ([]rendered, map[string]int) {
	buffer := []rendered{}
	info := make(map[string]int)
	node.print(&buffer, info, situ{path: []int{}})
	return buffer, info
}

func (node Var) keyPress(ch rune, offset int) (Node, []int, int) {
	switch ch {
	case '!':
		switch node.label {
		case "match":
			return Call{Call{Case{""}, Fn{"", Vacant{}}}, NoCases{}}, []int{0, 0}, 0
		}
	}
	// path.root
	return node, []int{}, offset
}
func (node Call) keyPress(ch rune, offset int) (Node, []int, int) {
	switch ch {
	case 'a':
		switch offset {
		case 0:
			// keypress on func
		default:
			// keypress on arg
			// call with new line after can actually delete the brackets so move to select child
		}
	}
	// path.root
	return node, []int{}, offset
}

func (node Vacant) keyPress(ch rune, offset int) (Node, int) {
	switch ch {
	case 'a':
		return Var{string(ch)}, 1
	}
	return node, offset
}

func (node String) keyPress(ch rune, offset int) (String, int) {
	switch ch {
	case 'a':
		value := node.value[:offset] + string(ch) + node.value[offset:]
		return String{value}, offset + 1
	}
	return node, offset
}

type editor struct {
	cursor Point
	panel  []rendered
	shift  Point
	size   Point
}

func (e editor) keyPress(ch rune) {
	// catch arrow movement
	path := []int{}
	// get cursor
	updated, offset := String{"foo"}.keyPress(ch, 2)
	// path and offset after edit
	buffer, info := Print(updated)
	start, ok := info[pathToString(path)]
	if !ok {
		panic("invalid path")
	}
	// TODO panel test
	position := XYinPage(buffer, start+offset)
	if position.X < e.shift.X {
		e.shift.X = position.X
	}
	if position.Y < e.shift.Y {
		e.shift.Y = position.Y
	}
	if e.shift.X+e.size.X < position.X {
		e.shift.X = position.X - e.size.X
	}
	if e.shift.Y+e.size.Y < position.Y {
		e.shift.Y = position.Y - e.size.Y
	}
	// TODO print on screen
	// cursor = position - shift
	// point arithmatic in file
}

func XYinPage(buffer []rendered, index int) Point {
	// can't use string because rendered
	x := 0
	y := 0
	newline := false
	for _, r := range buffer[:index+1] {
		if newline {
			x = 0
			y += 1
			newline = false
		} else {
			x += 1
		}
		if r.charachter == '\n' {
			newline = true
		}
	}
	return Point{x, y}
}

func TestPrinting(t *testing.T) {
	source := String{"hey"}
	buffer := []rendered{}
	info := make(map[string]int)
	source.print(&buffer, info, situ{path: []int{}})

	fmt.Printf("%#v\n", info)

	// screen 2x 2
	// tests := []struct {
	// 	source Node
	// 	want []rendered
	// }{}
}
