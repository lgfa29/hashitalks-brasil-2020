datacenter = "homelab"
data_dir   = "/Users/laoqui/go/src/github.com/lgfa29/from-legacy-to-nomad/data/nomad"

client {
  enabled = true
}

#server {
#  enabled          = true
#  bootstrap_expect = 3
#}

plugin "raw_exec" {
  config {
    enabled = true
  }
}
