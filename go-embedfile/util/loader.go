package main

import (
	"io"
	"os"
)

func main() {
	out, _ := os.Create("embed.go")
	out.Write([]byte("package main \n\nconst (\n"))

	out.Write([]byte("PEMFile = `"))
	thefile, err := os.Open("/Volumes/development/golang/src/github.com/widnyana/embedfile/sample.txt")
	if err != nil {
		panic(err)
	}
	io.Copy(out, thefile)
	out.Write([]byte("`\n)\n"))
}
