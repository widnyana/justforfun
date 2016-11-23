package main

import "fmt"

//go:generate go run util/loader.go

func main() {
	fmt.Printf(">>> %v", PEMFile)
}
