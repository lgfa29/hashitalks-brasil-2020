job "macos" {
  type        = "batch"
  datacenters = ["homelab"]

  parameterized {
    meta_required = ["title"]
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "darwin"
  }

  group "alert" {
    task "alert" {
      driver = "raw_exec"
      config {
        command = "osascript"
        args    = ["-e", "display alert \"${NOMAD_META_title}\" message \"Estou rodando na allocation ${NOMAD_ALLOC_ID}\""]
      }
    }
  }
}
