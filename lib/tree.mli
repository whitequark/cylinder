type entry = {
  mutable parent    : entry option;
  mutable name      : string;
  mutable modified  : modified;
          content   : content;
}
and modified = Uuidm.t * Timestamp.t
and content =
| Directory of directory
| File
and directory = {
  mutable children  : entry list;
}

val string_of_entry : entry -> string

val watch           : author:Uuidm.t -> Pathname.t -> entry Lwt.t
