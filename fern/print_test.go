package fern

import (
	"testing"

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
				{'x', []int{}, 0},
				{'\n', []int{}, 1},
			},
			map[string]int{"[]": 0},
		},
		{
			Vacant{""},
			[]rendered{
				{'t', []int{}, 0},
				{'o', []int{}, 1},
				{'d', []int{}, 2},
				{'o', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 0},
		},
		{
			String{"hey"},
			[]rendered{
				{'"', []int{}, -1},
				{'h', []int{}, 0},
				{'e', []int{}, 1},
				{'y', []int{}, 2},
				{'"', []int{}, 3},
				{'\n', []int{}, -1},
			},
			map[string]int{"[]": 1},
		},
		{
			Integer{10},
			[]rendered{
				{'1', []int{}, 0},
				{'0', []int{}, 1},
				{'\n', []int{}, 2},
			},
			map[string]int{"[]": 0},
		},
		{
			Tail{},
			[]rendered{
				{'[', []int{}, -1},
				{']', []int{}, 0},
				{'\n', []int{}, -1},
			},
			map[string]int{"[]": 1},
		},
		{
			Select{"name"},
			[]rendered{
				{'.', []int{}, -1},
				{'n', []int{}, 0},
				{'a', []int{}, 1},
				{'m', []int{}, 2},
				{'e', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 1},
		},
		{
			Perform{"Log"},
			[]rendered{
				{'p', []int{}, -1},
				{'e', []int{}, -1},
				{'r', []int{}, -1},
				{'f', []int{}, -1},
				{'o', []int{}, -1},
				{'r', []int{}, -1},
				{'m', []int{}, -1},
				{' ', []int{}, -1},
				{'L', []int{}, 0},
				{'o', []int{}, 1},
				{'g', []int{}, 2},
				{'\n', []int{}, 3},
			},
			map[string]int{"[]": 8},
		},
		{
			Call{Var{"x"}, String{""}},
			[]rendered{
				{'x', []int{0}, 0},
				{'(', []int{}, 0},
				{'"', []int{1}, -1},
				{'"', []int{1}, 0},
				{')', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		},
		{
			Call{Perform{"Log"}, Integer{5}},
			[]rendered{
				{'p', []int{0}, -1},
				{'e', []int{0}, -1},
				{'r', []int{0}, -1},
				{'f', []int{0}, -1},
				{'o', []int{0}, -1},
				{'r', []int{0}, -1},
				{'m', []int{0}, -1},
				{' ', []int{0}, -1},
				{'L', []int{0}, 0},
				{'o', []int{0}, 1},
				{'g', []int{0}, 2},
				{'(', []int{}, 0},
				{'5', []int{1}, 0},
				{')', []int{}, 2},
				{'\n', []int{}, 3},
			},
			map[string]int{"[]": 11, "[0]": 8, "[1]": 12},
		},
		{
			Call{Tag{"Ok"}, Var{"x"}},
			[]rendered{
				{'O', []int{0}, 0},
				{'k', []int{0}, 1},
				{'(', []int{}, 0},
				{'x', []int{1}, 0},
				{')', []int{}, 2},
				{'\n', []int{}, 3},
			},
			map[string]int{"[]": 2, "[0]": 0, "[1]": 3},
		},
		{
			Let{"a", Integer{1}, Let{"b", Integer{2}, Integer{3}}},
			[]rendered{
				{'l', []int{}, -1},
				{'e', []int{}, -1},
				{'t', []int{}, -1},
				{' ', []int{}, -1},
				{'a', []int{}, 0},
				{' ', []int{}, 1},
				{'=', []int{}, -1},
				{' ', []int{}, -1},
				{'1', []int{0}, 0},
				{'\n', []int{0}, 1},
				{'l', []int{1}, -1},
				{'e', []int{1}, -1},
				{'t', []int{1}, -1},
				{' ', []int{1}, -1},
				{'b', []int{1}, 0},
				{' ', []int{1}, 1},
				{'=', []int{1}, -1},
				{' ', []int{1}, -1},
				{'2', []int{1, 0}, 0},
				{'\n', []int{1, 0}, 1},
				{'3', []int{1, 1}, 0},
				{'\n', []int{1, 1}, 1},
			},
			map[string]int{"[]": 4, "[0]": 8, "[1]": 14, "[1,0]": 18, "[1,1]": 20},
		},
		// TODO nested let
		{
			Call{Select{"a"}, Var{"x"}},
			[]rendered{
				{'x', []int{1}, 0},
				// Don't have any reference to call node but this is ok - Nope
				// Needs to be ref to call node because arg might be a block or other
				{'.', []int{}, 0},
				{'a', []int{0}, 0},
				{'\n', []int{0}, 1},
			},
			map[string]int{"[1]": 0, "[0]": 2},
		},
		// TODO select sugar
		// TODO case statement
	}

	for _, tt := range tests {
		rendered, info := Print(tt.source)
		assert.Equal(t, tt.buffer, rendered)
		assert.Equal(t, tt.info, info)
	}
}
