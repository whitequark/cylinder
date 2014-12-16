type encoding = [ `None [@key 1] | `LZ4 [@key 2] ]
[@@deriving protobuf]

let encoding_to_string enc =
  match enc with
  | `None -> "None"
  | `LZ4  -> "LZ4"

let encoding_of_string str =
  match str with
  | "None" -> Some `None
  | "LZ4"  -> Some `LZ4
  | _ -> None

type data = {
  encoding  : encoding [@key  1] [@default `None] [@bare];
  content   : bytes    [@key 15];
}
[@@deriving protobuf]

let data_of_bytes bytes =
  { encoding = `None; content = bytes }

let data_to_bytes data =
  match data with
  | { encoding = `None; content } -> content
  | _ -> assert false
