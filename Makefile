all: build test

build:
	ocamlbuild -use-ocamlfind cylinderd.native

test:
	ocamlbuild -use-ocamlfind lib_test/test_cylinder.native --

clean:
	ocamlbuild -clean

dep:
	opam install ounit sexplib extlib inotify uuidm
