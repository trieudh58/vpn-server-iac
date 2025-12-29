variable "tenancy_ocid" {
  description = "The OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "The OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "The fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to your private API key"
  type        = string
}

variable "region" {
  description = "The OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
}

variable "instance_shape" {
  description = "The shape of the instance"
  type        = string
  # default     = "VM.Standard.E2.1.Micro"
  default     = "VM.Standard.A1.Flex"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "availability_domain_index" {
  description = "Index of the availability domain to use (0, 1, or 2)"
  type        = number
  default     = 0
}

variable "fault_domain" {
  description = "Fault domain to use for the instance (FAULT-DOMAIN-1, FAULT-DOMAIN-2, or FAULT-DOMAIN-3). Leave null for automatic assignment."
  type        = string
  default     = null
}
