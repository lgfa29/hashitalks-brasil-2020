job "win" {
  type        = "batch"
  datacenters = ["homelab"]

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "windows"
  }

  group "calc" {
    task "calc" {
      driver = "raw_exec"
      config {
        command = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
        args    = ["--kiosk", "https://www.datocms-assets.com/2885/1588889572-nomadprimarylogofullcolorrgb.svg"]
      }
    }
  }
}
