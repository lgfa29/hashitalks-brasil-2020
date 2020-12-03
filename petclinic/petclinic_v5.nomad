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
      auto_promote     = true
    }

    network {
      port "http" {
        to = 8080
      }
    }

    task "petclinic" {
      driver = "docker"

      config {
        image = "laoqui/spring-petclinic:v2.0"
        ports = ["http"]
      }

      resources {
        memory = 512
      }
    }
  }
}
