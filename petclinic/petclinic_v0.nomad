job "petclinic" {
  datacenters = ["dc1"]

  group "petclinic" {
    network {
      port "http" {
        to     = 8080
        static = 8080
      }
    }

    task "petclinic" {
      driver = "java"

      config {
        jar_path    = "local/spring-petclinic-1.0.jar"
        jvm_options = ["-Xmx512m", "-Xms256m"]
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
