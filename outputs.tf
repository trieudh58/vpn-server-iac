output "instance_id" {
  description = "OCID of the created instance"
  value       = oci_core_instance.vpn_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the instance"
  value       = oci_core_instance.vpn_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the instance"
  value       = oci_core_instance.vpn_server.private_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${oci_core_instance.vpn_server.public_ip}"
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.vpn_vcn.id
}
