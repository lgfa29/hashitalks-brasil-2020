datacenter = "homelab"
data_dir   = "/Users/laoqui/go/src/github.com/lgfa29/from-legacy-to-nomad/data/consul"

server           = true
bootstrap_expect = 3

advertise_addr = "192.168.0.100"

ui = true

ports {
  grpc = 8502
}

connect {
  enabled = true
}
