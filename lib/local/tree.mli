type entry = {
  mutable parent    : entry option;
  mutable name      : string;
  mutable modified  : Timestamp.t;
          content   : content;
}
and content =
| Directory of directory
| File
and directory = {
  mutable children  : entry list;
}

val string_of_entry : entry -> string

val watch           : Pathname.t -> entry Lwt.t
