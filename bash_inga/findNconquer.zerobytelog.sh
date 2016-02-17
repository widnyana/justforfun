#!/usr/bin/env bash
#: Stolen from: http://superuser.com/a/363778
#:
#: find all files with size 0
#: pipe the names to the while loop
#: cut of the suffix (extension) part ${f%.*} (read man bash)
#: rm all other files with the same base

find . -type f -name "*log" -size 0 | | while read f; do rm "${f%.*}."* ; done
