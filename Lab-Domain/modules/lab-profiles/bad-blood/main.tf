resource "null_resource" "run_badblood" {
  triggers = {
    dc_ip = var.dc_ip
  }

  connection {
    type     = "winrm"
    host     = var.dc_ip
    user     = "Administrator"
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "90m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = ["cmd /c mkdir C:\\setup 2>nul || exit 0"]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/run-badblood.ps1"
    destination = "C:\\setup\\run-badblood.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\setup\\run-badblood.ps1"
    ]
  }
}
