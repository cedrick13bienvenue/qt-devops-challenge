variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint"
  type        = string
  default     = "https://192.168.160.13:8006/"
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID (user@realm!token)"
  type        = string
  default     = "exam@pve!candidate1"
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret (UUID)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node that hosts the template and the new VMs"
  type        = string
  default     = "server3"
}

variable "pool_id" {
  description = "Resource pool the VMs are created in (null = no pool)"
  type        = string
  default     = null
}

variable "template_vm_id" {
  description = "VMID of the Ubuntu 24.04 template to clone"
  type        = number
  default     = 9000
}

variable "datastore_id" {
  description = "Storage for VM disks and the cloud-init drive"
  type        = string
  default     = "local-lvm"
}

variable "cpu_type" {
  description = "QEMU CPU model; x86-64-v3 exposes AVX/AVX2, required by MongoDB 5+"
  type        = string
  default     = "x86-64-v3"
}

variable "network_bridge" {
  description = "Proxmox bridge the VM NICs attach to"
  type        = string
  default     = "vmbr0"
}

variable "network_cidr_prefix" {
  description = "Prefix length of the LAN (192.168.160.0/24)"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway used with static IPs"
  type        = string
  default     = "192.168.160.1"
}

variable "dns_servers" {
  description = "DNS servers pushed through cloud-init"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "vm_username" {
  description = "Login user created on every VM by cloud-init"
  type        = string
  default     = "cedrick-bienvenue"
}

variable "ssh_public_key_path" {
  description = "Public key installed for vm_username"
  type        = string
  default     = "~/.ssh/qt_exam.pub"
}

variable "vm_password" {
  description = "Password for vm_username (console login and examiner access)"
  type        = string
  sensitive   = true
}

variable "ansible_inventory_path" {
  description = "Where the generated Ansible inventory is written, relative to iac/"
  type        = string
  default     = "../ansible/inventory/hosts.ini"
}

variable "vms" {
  description = "VMs to create, keyed by VM name; omit ip for DHCP"
  type = map(object({
    vm_id     = number
    role      = string
    ip        = optional(string)
    cores     = optional(number, 4)
    memory_mb = optional(number, 4096)
    disk_gb   = optional(number, 30)
  }))

  validation {
    condition     = alltrue([for vm in values(var.vms) : vm.ip == null || can(cidrhost("${vm.ip}/32", 0))])
    error_message = "Each vms[*].ip must be omitted (DHCP) or be a valid IPv4 address."
  }

  default = {
    "c3-docker-host" = {
      vm_id = 4101
      role  = "docker"
      ip    = "192.168.160.210"
    }
    "c3-k8s-master" = {
      vm_id = 4102
      role  = "k8s-master"
      ip    = "192.168.160.211"
    }
    "c3-k8s-worker-1" = {
      vm_id = 4103
      role  = "k8s-worker"
      ip    = "192.168.160.212"
    }
    "c3-k8s-worker-2" = {
      vm_id = 4104
      role  = "k8s-worker"
      ip    = "192.168.160.213"
    }
  }
}
