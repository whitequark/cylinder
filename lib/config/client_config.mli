type client_config = {
  secret_key  : Box.secret_key;
  public_key  : Box.public_key;
  server_key  : Box.public_key;
  server_host : string;
  server_port : int;
}

val client_config_of_string : string -> client_config
val client_config_to_string : client_config -> string
