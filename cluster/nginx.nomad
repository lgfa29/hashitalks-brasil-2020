job "nginx" {
  datacenters = ["homelab"]

  constraint {
    attribute = "${attr.kernel.name}"
    operator  = "!="
    value     = "windows"
  }

  group "nginx" {
    count = 4

    network {
      port "http" {
        static = 80
        to     = 80
      }
    }

    service {
      name = "nginx"
      port = "http"
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:1.18"
        ports = ["http"]
        volumes = [
          "local:/etc/nginx/conf.d",
        ]
      }

      template {
        data          = <<EOF
upstream backend {
{{ range service "live.petclinic" }}
  server {{ .Address }}:{{ .Port }};
{{ else }}server 127.0.0.1:65535; # force a 502
{{ end }}
}

server {
  listen 80;

  location / {
    proxy_pass http://backend;
  }
}
EOF
        destination   = "local/load-balancer.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
    }
  }
}
