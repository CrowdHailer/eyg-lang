package fern

import (
	"fmt"
	"testing"

	"github.com/gdamore/tcell/v2"
	"github.com/stretchr/testify/assert"
)

func TestPrinting(t *testing.T) {
	tests := []struct {
		source Node
		buffer []rendered
		info   map[string]int
	}{
		{
			Var{"x"},
			[]rendered{
				{'x', []int{}, 0, tcell.StyleDefault},
				{'\n', []int{}, 1, tcell.StyleDefault},
			},
			map[string]int{"[]": 0},
		},
		{
			Vacant{""},
			[]rendered{
				{'t', []int{}, 0, tcell.StyleDefault},
				{'o', []int{}, 1, tcell.StyleDefault},
				{'d', []int{}, 2, tcell.StyleDefault},
				{'o', []int{}, 3, tcell.StyleDefault},
				{'\n', []int{}, 4, tcell.StyleDefault},
			},
			map[string]int{"[]": 0},
		},
		{
			String{"hey"},
			[]rendered{
				{'"', []int{}, -1, tcell.StyleDefault},
				{'h', []int{}, 0, tcell.StyleDefault},
				{'e', []int{}, 1, tcell.StyleDefault},
				{'y', []int{}, 2, tcell.StyleDefault},
				{'"', []int{}, 3, tcell.StyleDefault},
				{'\n', []int{}, -1, tcell.StyleDefault},
			},
			map[string]int{"[]": 1},
		},
		{
			Integer{10},
			[]rendered{
				{'1', []int{}, 0, tcell.StyleDefault},
				{'0', []int{}, 1, tcell.StyleDefault},
				{'\n', []int{}, 2, tcell.StyleDefault},
			},
			map[string]int{"[]": 0},
		},
		{
			Tail{},
			[]rendered{
				{'[', []int{}, -1, tcell.StyleDefault},
				{']', []int{}, 0, tcell.StyleDefault},
				{'\n', []int{}, -1, tcell.StyleDefault},
			},
			map[string]int{"[]": 1},
		},
		{
			Select{"name"},
			[]rendered{
				{'.', []int{}, -1, tcell.StyleDefault},
				{'n', []int{}, 0, tcell.StyleDefault},
				{'a', []int{}, 1, tcell.StyleDefault},
				{'m', []int{}, 2, tcell.StyleDefault},
				{'e', []int{}, 3, tcell.StyleDefault},
				{'\n', []int{}, 4, tcell.StyleDefault},
			},
			map[string]int{"[]": 1},
		},
		{
			Perform{"Log"},
			[]rendered{
				{'p', []int{}, -1, tcell.StyleDefault},
				{'e', []int{}, -1, tcell.StyleDefault},
				{'r', []int{}, -1, tcell.StyleDefault},
				{'f', []int{}, -1, tcell.StyleDefault},
				{'o', []int{}, -1, tcell.StyleDefault},
				{'r', []int{}, -1, tcell.StyleDefault},
				{'m', []int{}, -1, tcell.StyleDefault},
				{' ', []int{}, -1, tcell.StyleDefault},
				{'L', []int{}, 0, tcell.StyleDefault},
				{'o', []int{}, 1, tcell.StyleDefault},
				{'g', []int{}, 2, tcell.StyleDefault},
				{'\n', []int{}, 3, tcell.StyleDefault},
			},
			map[string]int{"[]": 8},
		},
		// Fn test
		{
			Call{Var{"x"}, String{""}},
			[]rendered{
				{'x', []int{0}, 0, tcell.StyleDefault},
				{'(', []int{}, 0, tcell.StyleDefault},
				{'"', []int{1}, -1, tcell.StyleDefault},
				{'"', []int{1}, 0, tcell.StyleDefault},
				{')', []int{}, 3, tcell.StyleDefault},
				{'\n', []int{}, 4, tcell.StyleDefault},
			},
			map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		},
		{
			Call{Perform{"Log"}, Integer{5}},
			[]rendered{
				{'p', []int{0}, -1, tcell.StyleDefault},
				{'e', []int{0}, -1, tcell.StyleDefault},
				{'r', []int{0}, -1, tcell.StyleDefault},
				{'f', []int{0}, -1, tcell.StyleDefault},
				{'o', []int{0}, -1, tcell.StyleDefault},
				{'r', []int{0}, -1, tcell.StyleDefault},
				{'m', []int{0}, -1, tcell.StyleDefault},
				{' ', []int{0}, -1, tcell.StyleDefault},
				{'L', []int{0}, 0, tcell.StyleDefault},
				{'o', []int{0}, 1, tcell.StyleDefault},
				{'g', []int{0}, 2, tcell.StyleDefault},
				{'(', []int{}, 0, tcell.StyleDefault},
				{'5', []int{1}, 0, tcell.StyleDefault},
				{')', []int{}, 2, tcell.StyleDefault},
				{'\n', []int{}, 3, tcell.StyleDefault},
			},
			map[string]int{"[]": 11, "[0]": 8, "[1]": 12},
		},
		{
			Call{Tag{"Ok"}, Var{"x"}},
			[]rendered{
				{'O', []int{0}, 0, tcell.StyleDefault},
				{'k', []int{0}, 1, tcell.StyleDefault},
				{'(', []int{}, 0, tcell.StyleDefault},
				{'x', []int{1}, 0, tcell.StyleDefault},
				{')', []int{}, 2, tcell.StyleDefault},
				{'\n', []int{}, 3, tcell.StyleDefault},
			},
			map[string]int{"[]": 2, "[0]": 0, "[1]": 3},
		},
		{
			Let{"a", Integer{1}, Let{"b", Integer{2}, Integer{3}}},
			[]rendered{
				{'l', []int{}, -1, tcell.StyleDefault},
				{'e', []int{}, -1, tcell.StyleDefault},
				{'t', []int{}, -1, tcell.StyleDefault},
				{' ', []int{}, -1, tcell.StyleDefault},
				{'a', []int{}, 0, tcell.StyleDefault},
				{' ', []int{}, 1, tcell.StyleDefault},
				{'=', []int{}, -1, tcell.StyleDefault},
				{' ', []int{}, -1, tcell.StyleDefault},
				{'1', []int{0}, 0, tcell.StyleDefault},
				{'\n', []int{0}, 1, tcell.StyleDefault},
				{'l', []int{1}, -1, tcell.StyleDefault},
				{'e', []int{1}, -1, tcell.StyleDefault},
				{'t', []int{1}, -1, tcell.StyleDefault},
				{' ', []int{1}, -1, tcell.StyleDefault},
				{'b', []int{1}, 0, tcell.StyleDefault},
				{' ', []int{1}, 1, tcell.StyleDefault},
				{'=', []int{1}, -1, tcell.StyleDefault},
				{' ', []int{1}, -1, tcell.StyleDefault},
				{'2', []int{1, 0}, 0, tcell.StyleDefault},
				{'\n', []int{1, 0}, 1, tcell.StyleDefault},
				{'3', []int{1, 1}, 0, tcell.StyleDefault},
				{'\n', []int{1, 1}, 1, tcell.StyleDefault},
			},
			map[string]int{"[]": 4, "[0]": 8, "[1]": 14, "[1,0]": 18, "[1,1]": 20},
		},
		{
			Let{"a", Let{"b", Integer{1}, Integer{2}}, Integer{3}},
			[]rendered{
				{'l', []int{}, -1, tcell.StyleDefault},
				{'e', []int{}, -1, tcell.StyleDefault},
				{'t', []int{}, -1, tcell.StyleDefault},
				{' ', []int{}, -1, tcell.StyleDefault},
				{'a', []int{}, 0, tcell.StyleDefault},
				{' ', []int{}, 1, tcell.StyleDefault},
				{'=', []int{}, -1, tcell.StyleDefault},
				{' ', []int{}, -1, tcell.StyleDefault},
				{'{', nil, -1, tcell.StyleDefault},
				{'\n', nil, -1, tcell.StyleDefault},
				{' ', nil, -1, tcell.StyleDefault},
				{' ', nil, -1, tcell.StyleDefault},
				{'l', []int{0}, -1, tcell.StyleDefault},
				{'e', []int{0}, -1, tcell.StyleDefault},
				{'t', []int{0}, -1, tcell.StyleDefault},
				{' ', []int{0}, -1, tcell.StyleDefault},
				{'b', []int{0}, 0, tcell.StyleDefault},
				{' ', []int{0}, 1, tcell.StyleDefault},
				{'=', []int{0}, -1, tcell.StyleDefault},
				{' ', []int{0}, -1, tcell.StyleDefault},
				{'1', []int{0, 0}, 0, tcell.StyleDefault},
				{'\n', []int{0, 0}, 1, tcell.StyleDefault},
				{' ', nil, -1, tcell.StyleDefault},
				{' ', nil, -1, tcell.StyleDefault},
				{'2', []int{0, 1}, 0, tcell.StyleDefault},
				{'\n', []int{0, 1}, 1, tcell.StyleDefault},
				{'}', nil, -1, tcell.StyleDefault},
				{'\n', nil, -1, tcell.StyleDefault},
				{'3', []int{1}, 0, tcell.StyleDefault},
				{'\n', []int{1}, 1, tcell.StyleDefault},
			},
			map[string]int{"[]": 4, "[0]": 16, "[0,0]": 20, "[0,1]": 24, "[1]": 28},
		},
		// Sugar
		{
			// buld comma where
			// [1, ]
			// [1, ..x]
			// , needs to be on call because may be block
			// [{ .. }, 2]
			// only top element and tail clickable
			// press comma on brackets can't go into string because quotes separate but numbers can extend number
			// [x] comma on tail -> [x, hole]
			// [] comma on tail -> [hole]
			// [a, b] comma on comma -> [a, hole, b] where what your on becomes is the call stack
			Call{Call{Cons{}, Integer{1}}, Call{Call{Cons{}, Integer{2}}, Tail{}}},
			[]rendered{
				{'[', []int{}, 0, tcell.StyleDefault},
				{'1', []int{0, 1}, 0, tcell.StyleDefault},
				{',', []int{1}, 0, tcell.StyleDefault},
				{' ', []int{1}, 1, tcell.StyleDefault},
				// Nothing is zero widith so can check if at tail with offset > 2
				// can start with '[' or ', '
				{'2', []int{1, 0, 1}, 0, tcell.StyleDefault}, // comma on number can make a list because that would be list in list
				// make this one because try and not go up the list for edits
				{']', []int{1}, 3, tcell.StyleDefault}, // or should this be the call above with offset for inse, tcell.StyleDefaultrt
				{'\n', []int{1}, 4, tcell.StyleDefault},
			},
			map[string]int{"[0,1]": 1, "[1,0,1]": 4},
		},
		{
			Call{Var{"x"}, Tail{}},
			[]rendered{
				{'x', []int{0}, 0, tcell.StyleDefault},
				{'(', []int{}, 0, tcell.StyleDefault},
				{'[', []int{1}, -1, tcell.StyleDefault},
				{']', []int{1}, 0, tcell.StyleDefault},
				{')', []int{}, 3, tcell.StyleDefault},
				{'\n', []int{}, 4, tcell.StyleDefault},
			},
			map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		},
		// {
		// 	Call{Call{Cons{}, Var{"x"}}, Var{"y"}},
		// 	[]rendered{
		// 		{'[', []int{}, 0, tcell.StyleDefault},
		// 		{'x', []int{1, 0}, 0, tcell.StyleDefault},
		// 		{',', []int{1}, -1, tcell.StyleDefault},
		// 		{' ', []int{1}, 0, tcell.StyleDefault},
		// 		{'.', []int{1}, 3, tcell.StyleDefault},
		// 		{'.', []int{1}, 3, tcell.StyleDefault},
		// 		// TODO Doesn't work with offset in var an in tail at the same time
		// 		// should call always be -1 it's a text thing after all
		// 		// Only need is differationation between before and after
		// 		{'y', []int{1}, 3, tcell.StyleDefault},
		// 		{']', []int{1}, 3, tcell.StyleDefault},
		// 		{'\n', []int{1}, 4, tcell.StyleDefault},
		// 	},
		// 	map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		// },
		{
			Call{Select{"a"}, Var{"x"}},
			[]rendered{
				{'x', []int{1}, 0, tcell.StyleDefault},
				// Don't have any reference to call node but this is ok - Nope
				// Needs to be ref to call node because arg might be a block or other
				{'.', []int{}, 0, tcell.StyleDefault},
				{'a', []int{0}, 0, tcell.StyleDefault},
				{'\n', []int{0}, 1, tcell.StyleDefault},
			},
			map[string]int{"[1]": 0, "[0]": 2},
		},
		// {
		// 	Call{Call{Extend{"a"}, Integer{1}}, Call{Call{Extend{"b"}, Integer{2}}, Empty{}}},
		// 	[]rendered{
		// 		{'{', []int{}, 0, tcell.StyleDefault},
		// 		{'a', []int{0, 0}, 0, tcell.StyleDefault},
		// 		{':', []int{0, 0}, 1, tcell.StyleDefault},
		// 		{' ', []int{}, 0, tcell.StyleDefault},
		// 		{'1', []int{0, 1}, 0, tcell.StyleDefault},
		// 		{',', []int{1}, 0, tcell.StyleDefault},
		// 		{' ', []int{1}, 1, tcell.StyleDefault},
		// 		{'b', []int{}, 0, tcell.StyleDefault},
		// 		{':', []int{}, 0, tcell.StyleDefault},
		// 		{' ', []int{}, 0, tcell.StyleDefault},
		// 		{'2', []int{1, 0, 1}, 0}, // comma on number can make a list because that would be list in list
		// 		// make this one because try and not go up the list for edits
		// 		{'}', []int{1}, 3}, // or should this be the call above with offset for inse, tcell.StyleDefaultrt
		// 		{'\n', []int{1}, 4, tcell.StyleDefault},
		// 	},
		// 	map[string]int{"[0,1]": 1, "[1,0,1]": 4},
		// },
		// TODO case statement
	}

	for _, tt := range tests {
		rendered, info := Print(tt.source)

		assertRendered(t, tt.buffer, rendered)
		assert.Equal(t, tt.info, info)
	}
}

func assertRendered(t *testing.T, expected, actual []rendered) {
	expectedText := renderedText(expected)
	actualText := renderedText(actual)
	if expectedText != actualText {
		t.Logf("Not equal:\nexpected: %s\nactual:   %s", expectedText, actualText)
		t.Fail()
	}

	expectedPaths := renderedPaths(expected)
	actualPaths := renderedPaths(actual)
	assert.Equal(t, expectedPaths, actualPaths)

	expectedOffsets := renderedOffsets(expected)
	actualOffsets := renderedOffsets(actual)
	assert.Equal(t, expectedOffsets, actualOffsets)
}

func renderedText(buffer []rendered) string {
	out := ""
	for _, r := range buffer {
		out += string(r.character)
	}
	// Shows newline charachters
	return fmt.Sprintf("%#v", out)
}

func renderedPaths(buffer []rendered) []string {
	var out []string
	for _, r := range buffer {
		out = append(out, pathToString(r.path))
	}
	return out
}

func renderedOffsets(buffer []rendered) []int {
	var out []int
	for _, r := range buffer {
		out = append(out, r.offset)
	}
	return out
}
