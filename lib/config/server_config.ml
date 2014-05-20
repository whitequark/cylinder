type server_config = {
  secret_key : Box.secret_key;
  public_key : Box.public_key;
}

let server_config_of_string str =
  let json = Yojson.Basic.from_string str in
  let open Yojson.Basic.Util in
  try
    { secret_key =
        json |> member "secret_key" |> to_string |> Box.secret_key_of_string |> Option.get;
      public_key =
        json |> member "public_key" |> to_string |> Box.public_key_of_string |> Option.get; }
  with Option.No_value ->
    failwith "Corrupted configuration"

let server_config_to_string cfg =
  let json : Yojson.Basic.json =
    `Assoc [
      "secret_key", `String (Box.secret_key_to_string cfg.secret_key);
      "public_key", `String (Box.public_key_to_string cfg.public_key)]
  in
  Yojson.Basic.pretty_to_string json
