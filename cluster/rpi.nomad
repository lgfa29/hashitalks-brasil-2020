job "rpi" {
  datacenters = ["homelab"]
  type        = "batch"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "nomad-rpi-3"
  }

  periodic {
    cron = "*/2 * * * * * *"
  }

  group "led" {
    task "export-gpio" {
      driver = "raw_exec"

      lifecycle {
        hook = "prestart"
      }

      config {
        command = "bash"
        args    = ["-c", "if [ ! -f '/sys/class/gpio/gpio17/value' ]; then echo '17' > /sys/class/gpio/export; fi"]
      }
    }

    task "set-gpio-direction" {
      driver = "raw_exec"

      lifecycle {
        hook = "prestart"
      }

      config {
        command = "bash"
        args    = ["-c", "if [ -f '/sys/class/gpio/gpio17/value' ]; then echo 'out' > /sys/class/gpio/gpio17/direction; fi"]
      }
    }

    task "led" {
      driver = "raw_exec"

      config {
        command = "bash"
        args    = ["-c", "echo '1' > /sys/class/gpio/gpio17/value && sleep 1 && echo '0' > /sys/class/gpio/gpio17/value"]
      }
    }
  }
}
