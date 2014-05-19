(* Base64 with URL and Filename Safe Alphabet (RFC 4648 'base64url' encoding) *)
let base64_enctbl = [|
  'A';'B';'C';'D';'E';'F';'G';'H';'I';'J';'K';'L';'M';'N';'O';'P';
  'Q';'R';'S';'T';'U';'V';'W';'X';'Y';'Z';'a';'b';'c';'d';'e';'f';
  'g';'h';'i';'j';'k';'l';'m';'n';'o';'p';'q';'r';'s';'t';'u';'v';
  'w';'x';'y';'z';'0';'1';'2';'3';'4';'5';'6';'7';'8';'9';'-';'_'
|]
let base64_dectbl = Base64.make_decoding_table base64_enctbl

let encode = Base64.str_encode ~tbl:base64_enctbl

let decode str =
  try  Some (Base64.str_decode ~tbl:base64_dectbl str)
  with Base64.Invalid_char -> None
