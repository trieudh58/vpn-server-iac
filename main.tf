# Cloud-init configuration for WireGuard installation
locals {
  cloud_init = file("${path.module}/cloud-init.yaml")
}

# Get the list of availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get the latest Ubuntu 24.04 image
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Virtual Cloud Network
resource "oci_core_vcn" "vpn_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "vpn-vcn"
  dns_label      = "vpnvcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "vpn_ig" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vpn_vcn.id
  display_name   = "vpn-internet-gateway"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "vpn_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vpn_vcn.id
  display_name   = "vpn-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.vpn_ig.id
  }
}

# Security List
resource "oci_core_security_list" "vpn_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vpn_vcn.id
  display_name   = "vpn-security-list"

  # Egress - Allow all outbound traffic
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Ingress - Allow SSH
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress - Allow ICMP
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = "0.0.0.0/0"
  }

  # Ingress - Allow VPN traffic (OpenVPN default port)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 1194
      max = 1194
    }
  }

  # Ingress - Allow VPN traffic (UDP)
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"

    udp_options {
      min = 1194
      max = 1194
    }
  }

  # Ingress - Allow WireGuard traffic (UDP)
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"

    udp_options {
      min = 51820
      max = 51820
    }
  }
}

# Subnet
resource "oci_core_subnet" "vpn_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.vpn_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "vpn-subnet"
  dns_label         = "vpnsubnet"
  route_table_id    = oci_core_route_table.vpn_rt.id
  security_list_ids = [oci_core_security_list.vpn_sl.id]
}

# Compute Instance
resource "oci_core_instance" "vpn_server" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "vpn-server"
  shape               = var.instance_shape

  shape_config {
    memory_in_gbs = 1
    ocpus         = 1
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.vpn_subnet.id
    display_name     = "vpn-server-vnic"
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }

  preserve_boot_volume = false
}
