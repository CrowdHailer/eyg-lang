package main

import (
	"context"
	_ "embed"
	"fmt"
	"log"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

//go:embed cozo_lib_wasm_bg.wasm
var addWasm []byte

func main() {
	fmt.Println(len(addWasm))

	ctx := context.Background()

	// Create a new WebAssembly Runtime.
	r := wazero.NewRuntime(ctx)
	defer r.Close(ctx) // This closes everything this Runtime created.

	// Instantiate WASI, which implements host functions needed for TinyGo to
	// implement `panic`.
	wasi_snapshot_preview1.MustInstantiate(ctx, r)

	// wazero.NewModuleConfig().
	mod, err := r.Instantiate(ctx, addWasm)
	// fmt.Println(mod.ExportedFunctionDefinitions())
	if err != nil {
		log.Panicf("failed to instantiate module: %v", err)
	}

	add := mod.ExportedFunction("add")
	results, err := add.Call(ctx, 1, 2)
	if err != nil {
		log.Panicf("failed to call add: %v", err)
	}
	fmt.Println(results)
}
