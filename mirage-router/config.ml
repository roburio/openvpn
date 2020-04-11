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

let monitor =
  let doc = Key.Arg.info ~doc:"monitor host IP" ["monitor"] in
  Key.(create "monitor" Arg.(opt (some ip_address) None doc))

let syslog =
  let doc = Key.Arg.info ~doc:"syslog host IP" ["syslog"] in
  Key.(create "syslog" Arg.(opt (some ip_address) None doc))

let name =
  let doc = Key.Arg.info ~doc:"Name of the unikernel" ["name"] in
  Key.(create "name" Arg.(opt string "as250" doc))

let keys = [ Key.abstract name ; Key.abstract monitor ; Key.abstract syslog ]

let management_stack = generic_stackv4v6 ~group:"management" (netif ~group:"management" "management")

let openvpn_handler =
  let packages =
    let pin = "git+https://github.com/roburio/openvpn.git" in
    [
      package "logs" ;
      package ~pin ~sublibs:["mirage"] "openvpn";
      package "mirage-kv";
      package ~min:"3.8.0" "mirage-runtime";
      package "provision";
      package ~sublibs:["mirage"] ~min:"0.3.0" "logs-syslog" ;
      package ~min:"0.0.2" "monitoring-experiments" ;
    ]
  in
  foreign
    ~keys
    ~packages
    "Unikernel.Main" (console @-> random @-> mclock @-> pclock @-> time @-> stackv4v6 @-> network @-> ethernet @-> arpv4 @-> ipv4 @-> provision @-> stackv4v6 @-> job)

let () =
  register "ovpn-router" [openvpn_handler $ default_console $ default_random $ default_monotonic_clock $ default_posix_clock $ default_time $ generic_stackv4v6 default_network $ private_netif $ private_ethernet $ private_arp $ private_ipv4 $ provision_impl $ management_stack ]
