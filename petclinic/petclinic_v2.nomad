job "petclinic" {
  datacenters = ["dc1"]

  group "petclinic" {
    count = 2

    network {
      port "http" {}
    }

    task "petclinic" {
      driver = "java"

      config {
        jar_path    = "local/spring-petclinic-1.0.jar"
        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
      }

      artifact {
        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v1.0/spring-petclinic-1.0.jar"
        destination = "local"
      }

      resources {
        memory = 512
      }
    }
  }
}
