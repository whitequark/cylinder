module Delta = struct
  type t = int64 [@@protobuf]

  let zero = 0L

  let of_milliseconds dut = dut
  let to_milliseconds dt  = dt

  let to_string dt =
    Printf.sprintf "%+Ldms" dt

  let add = Int64.add
  let sub = Int64.sub
  let div dt n = Int64.div dt (Int64.of_int n)
end

type t = int64 [@@protobuf]

let zero = 0L

let of_unix_time time =
  Int64.of_float (time *. 1000.)

let to_unix_time timestamp =
  (Int64.to_float timestamp) /. 1000.

let of_milliseconds time = time
let to_milliseconds timestamp = timestamp

let of_seconds = Int64.mul 1000L
let to_seconds = Int64.div 1000L

let to_string ?(format=`ISO8601) timestamp =
  let open Unix in
  let gmt = gmtime (to_unix_time timestamp) in
  match format with
  | `ISO8601 ->
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03LdZ"
      (1900 + gmt.tm_year) (1 + gmt.tm_mon) gmt.tm_mday
      gmt.tm_hour gmt.tm_min gmt.tm_sec (Int64.rem timestamp 1000L)
  | `HM -> Printf.sprintf "%02d:%02d" gmt.tm_hour gmt.tm_min
  | `MD -> Printf.sprintf "%02d-%02d" (1 + gmt.tm_mon) gmt.tm_mday

let now () =
  of_unix_time (Unix.gettimeofday ())

let diff a b = Int64.sub b a
let advance = Int64.add
let floor t p = Int64.sub t (Int64.rem t p)
