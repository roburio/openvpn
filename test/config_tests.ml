let pmsg =
  Alcotest.testable (fun ppf (`Msg s) -> Fmt.pf ppf "Error @[<v>(%s)@]" s)
    (fun (`Msg a) (`Msg b) -> String.equal a b)

let conf_map = Alcotest.testable
    Openvpn.Config.pp Openvpn.Config.(equal eq)

let parse_noextern conf =
  Openvpn.Config.parse_client ~string_of_file:(fun path ->
      Rresult.R.error_msgf
        "this test suite does not read external files, \
         but a config asked for: %S" path) conf

let minimal_config =
  let open Openvpn.Config in
  empty
  (* from {!Openvpn.Config.Defaults.client_config} *)
  |> add Ping_interval `Not_configured
  |> add Ping_timeout (`Restart 120)
  |> add Renegotiate_seconds 3600
  |> add Bind (Some (None, None)) (* TODO default to 1194 for servers? *)
  |> add Handshake_window 60
  |> add Transition_window 3600
  |> add Tls_timeout 2
  |> add Resolv_retry `Infinite
  |> add Auth_retry `None
  |> add Connect_timeout 120
  |> add Connect_retry_max `Unlimited
  |> add Proto (None, `Udp)
  (* Minimal contents of actual config file: *)
  |> add Tls_mode `Client
  |> add Auth_user_pass ("testuser","testpass")
  |> add Remote [`Ip (Ipaddr.of_string_exn "10.0.0.1"), 1194, `Udp]


let ok_minimal_client () =
  (* verify that we can parse a minimal good config. *)
  let basic =
    {|tls-client
    auth-user-pass [inline]
    <auth-user-pass>
testuser
testpass
</auth-user-pass>
remote 10.0.0.1|} in
  Alcotest.(check (result conf_map pmsg)) "basic conf works"
    (Ok minimal_config)
    (parse_noextern basic)

let auth_user_pass_trailing_whitespace () =
  (* Seems to me that the OpenVPN upstream accepts this and we don't.
     It should also be tested if the upstream version strips prefixed/trailing
     whitespace from the user/pass/end-block lines. TODO.
  *)
  let common =
    "client\n"
    ^ "remote 127.0.0.1\n"
    ^ "auth-user-pass [inline]\n"
    ^ "<auth-user-pass>\n"
    ^ "testuser\n"
    ^ "testpass\n" in
  let expected = common ^ "</auth-user-pass>" |> parse_noextern in
  let with_trailing = common ^ "\n</auth-user-pass>" |> parse_noextern in
  Alcotest.(check (result conf_map pmsg))
    "accept trailing whitespace in <auth-user-pass> blocks"
    expected with_trailing

let rport_precedence () =
  (* NOTE: at the moment this is expected to fail because we do not implement
     the rport directive correctly. TODO *)
  (* see https://github.com/roburio/openvpn/pull/12#issuecomment-581449319 *)
  let sample =
    {|
    tls-client
    auth-user-pass [inline]
    <auth-user-pass>
testuser
testpass
</auth-user-pass>

    remote 10.0.42.5
    remote 10.0.42.3 1194
    rport 1234
    remote 10.0.42.4
|} in
  let open Openvpn.Config in
  let sample = parse_client
      ~string_of_file:(fun _ -> Rresult.R.error_msg "oops")
      sample
  in
  let expected =
        {|
    tls-client
    auth-user-pass [inline]
    <auth-user-pass>
testuser
testpass
</auth-user-pass>

    remote 10.0.42.5 1234
    remote 10.0.42.3 1194
    rport 1234
    remote 10.0.42.4 1234
|} |> parse_noextern |> Rresult.R.get_ok
  in
  Alcotest.(check (result conf_map pmsg))
    "rport doesn't override explicits that coincide with the default"
    (Ok expected)
    (sample) ;
  let _ip1 = Ipaddr.of_string_exn "10.0.42.3" in
  let _ip2 = Ipaddr.of_string_exn "10.0.42.4" in
  let _ip3 = Ipaddr.of_string_exn "10.0.42.5" in
  () (* TODO check that the ports and remotes also match the written *)

let crowbar_fuzz_config () =
  Crowbar.add_test ~name:"Fuzzing doesn't crash Config.parse_client"
    [Crowbar.bytes] (fun s ->
        try Crowbar.check (ignore @@ parse_noextern s ; true)
        with _ -> Crowbar.bad_test ()
      )

let tests = [
  "minimal client config", `Quick, ok_minimal_client ;
  "auth-user-pass trailing whitespace", `Quick,
  auth_user_pass_trailing_whitespace ;
  "rport precedence", `Quick, rport_precedence ;
  "crowbar fuzzing", `Slow, crowbar_fuzz_config ;
]