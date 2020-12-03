job "petclinic" {
  datacenters = ["dc1"]

  group "petclinic" {
    count = 2

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

    task "petclinic" {
      driver = "java"

      config {
        jar_path    = "local/spring-petclinic-2.1.jar"
        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
      }

      artifact {
        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v2.1/spring-petclinic-2.1.jar"
        destination = "local"
      }

      resources {
        memory = 512
      }
    }
  }
}
