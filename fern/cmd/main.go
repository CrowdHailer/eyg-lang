package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/gdamore/tcell/v2"
	"github.com/midas-framework/project_wisdom/fern"
)

func main() {
	tcell.SetEncodingFallback(tcell.EncodingFallbackASCII)
	screen, err := tcell.NewScreen()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	if err = screen.Init(); err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}

	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	path := filepath.Join(dir, "saved.json")
	store := &fileStore{path}

	fern.New(screen, store)
}

type fileStore struct {
	path string
}

var _ fern.Store = (*fileStore)(nil)

func (store *fileStore) Load() ([]byte, error) {
	return os.ReadFile(store.path)
}

func (store *fileStore) Save(data []byte) error {
	return os.WriteFile(store.path, data, 0644)
}
