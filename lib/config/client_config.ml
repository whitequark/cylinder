 type client_config = {
  secret_key  : Box.secret_key;
  public_key  : Box.public_key;
  server_key  : Box.public_key;
  server_host : string;
  server_port : int;
}

let client_config_of_string str =
  let json = Yojson.Basic.from_string str in
  let open Yojson.Basic.Util in
  try
    { secret_key =
        json |> member "secret_key" |> to_string |> Box.secret_key_of_string |> Option.get;
      public_key =
        json |> member "public_key" |> to_string |> Box.public_key_of_string |> Option.get;
      server_key =
        json |> member "server" |> member "public_key" |> to_string |>
          Box.public_key_of_string |> Option.get;
      server_host = json |> member "server" |> member "host" |> to_string;
      server_port = json |> member "server" |> member "port" |> to_int; }
  with Option.No_value ->
    failwith "Corrupted configuration"

let client_config_to_string cfg =
  let json : Yojson.Basic.json =
    `Assoc [
      "secret_key", `String (Box.secret_key_to_string cfg.secret_key);
      "public_key", `String (Box.public_key_to_string cfg.public_key);
      "server", `Assoc [
        "public_key", `String (Box.public_key_to_string cfg.server_key);
        "host",       `String cfg.server_host;
        "port",       `Int    cfg.server_port]]
  in
  Yojson.Basic.pretty_to_string json
