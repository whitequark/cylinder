Cylinder
========

Building
--------

You need [OPAM](http://opam.ocaml.org).

```
opam switch 4.02.0+trunk
opam pin ocamlfind git://github.com/whitequark/ocaml-findlib
opam pin lwt git://github.com/whitequark/lwt#ppx
opam pin ppx_tools git://github.com/alainfrisch/ppx_tools
opam pin ppx_protobuf git://github.com/whitequark/ocaml-ppx_protobuf
opam pin ctypes git://github.com/yallop/ocaml-ctypes#whitequark-bytes
opam pin cmdliner git://github.com/dbuenzli/cmdliner
opam pin sodium git://github.com/whitequark/ocaml-sodium#zero-copy
opam pin zmq git://github.com/whitequark/ocaml-zmq#finalizers
opam pin lwt-zmq git://github.com/whitequark/lwt-zmq
opam pin utop git://github.com/diml/utop
opam install extlib extunix lwt inotify ppx_protobuf sodium lwt-zmq yojson utop oasis
./configure
make
```
