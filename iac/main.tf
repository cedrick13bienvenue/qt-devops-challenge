locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name            = each.key
  vm_id           = each.value.vm_id
  description     = "${each.value.role} - managed by Terraform"
  node_name       = var.proxmox_node
  pool_id         = var.pool_id
  tags            = ["qt-exam", each.value.role]
  on_boot         = true
  started         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single"

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.proxmox_node
    datastore_id = var.datastore_id
    full         = true
  }

  agent {
    enabled = true
    timeout = "5m"
  }

  cpu {
    sockets = 1
    cores   = each.value.cores
    type    = var.cpu_type
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk_gb
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  cdrom {
    interface = "ide2"
    file_id   = "none"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide0"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = each.value.ip == null ? "dhcp" : "${each.value.ip}/${var.network_cidr_prefix}"
        gateway = each.value.ip == null ? null : var.gateway
      }
    }

    user_account {
      username = var.vm_username
      keys     = [local.ssh_public_key]
      password = var.vm_password
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }
}
