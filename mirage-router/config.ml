open Mirage

type provision = Provision
let provision = Functoria.Type Provision

let private_netif = netif ~group:"private" "private"
let private_ethernet = etif private_netif
let private_arp = arp private_ethernet
let private_ipv4 = create_ipv4 ~group:"private" private_ethernet private_arp

let provision_impl =
  let open Functoria in
  let open Functoria_app in
  impl @@ object
    inherit base_configurable

    method ty = provision
    val name = Name.create ~prefix:"caravan" "prvs"
    method name = name
    method module_name = String.capitalize_ascii name
    method! packages =
      Key.pure [ package "provision" ]
    method! connect _ modname _ =
      Fmt.strf "return (%s.provision)" modname
    method! clean _info =
      Bos.OS.File.delete Fpath.(v name + "ml")
    method! build _info =
      let contents = Fmt.strf "let provision = Provision.unsafe_of_string \
                               \"PROVISION_\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\"" in
      let output_string oc v = output_string oc v ; Ok () in
      let res = Bos.OS.File.with_oc Fpath.(v name + "ml") output_string contents in
      Rresult.R.join res
  end

let openvpn_handler =
  let packages =
    let pin = "git+https://github.com/roburio/openvpn.git" in
    [
      package "logs" ;
      package ~pin ~sublibs:["mirage"] "openvpn";
      package "mirage-kv";
      package ~min:"3.8.0" "mirage-runtime";
      package "provision";
    ]
  in
  foreign
    ~packages
    "Unikernel.Main" (random @-> mclock @-> pclock @-> time @-> stackv4v6 @-> network @-> ethernet @-> arpv4 @-> ipv4 @-> provision @-> job)

let () =
  register "ovpn-router" [openvpn_handler $ default_random $ default_monotonic_clock $ default_posix_clock $ default_time $ generic_stackv4v6 default_network $ private_netif $ private_ethernet $ private_arp $ private_ipv4 $ provision_impl ]
