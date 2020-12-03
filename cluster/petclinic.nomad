job "petclinic" {
  datacenters = ["homelab"]

  group "petclinic" {
    count = 10

    update {
      max_parallel     = 1
      canary           = 2
      min_healthy_time = "30s"
      healthy_deadline = "5m"
      auto_revert      = true
      auto_promote     = false
    }

    network {
      port "http" {}
    }

    service {
      name = "petclinic"
      port = "http"

      tags        = ["live"]
      canary_tags = ["canary"]

      check {
        type     = "http"
        port     = "http"
        path     = "/"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "petclinic" {
      driver = "java"

      config {
        jar_path    = "local/spring-petclinic-2.0.jar"
        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
      }

      artifact {
        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v2.0/spring-petclinic-2.0.jar"
        destination = "local"
      }

      resources {
        memory = 512
      }
    }
  }
}
