# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# You must provide a value for each of these parameters.
# ---------------------------------------------------------------------------------------------------------------------

variable "ami_id" {
  description = "The ID of the AMI to run on each EC2 Instance. Should be an AMI built from the Packer template in examples/packer-docker-example/build.json."
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region to deploy into"
  default     = "eu-west-1"
}

variable "prefix" {
  description = "Prefix for resources"
}

variable "instance_name" {
  description = "The Name tag to set for the EC2 Instance."
  default     = "terratest-example"
}

variable "stats_port" {
  description = "The port the EC2 Instance should listen on for HTTP requests for statistics."
  default     = 5000
}

variable "dtax_healthcheck_port" {
  description = "The port the EC2 Instance should listen on for HTTP requests healthcheck for dtax."
  default     = 8080
}

variable "itax_healthcheck_port" {
  description = "The port the EC2 Instance should listen on for HTTP requests healthcheck for itax."
  default     = 8081
}

variable "dtax_port" {
  description = "The port the EC2 Instance should listen on for dtax proxy."
  default     = 9102
}

variable "itax_port" {
  description = "The port the EC2 Instance should listen on for itax proxy."
  default     = 9002
}

variable "haproxy_exporter_port" {
  description = "The port that exports haproxy prometheus metrics."
  default     = 9101
}

variable "node_export_port" {
  description = "The port that exports node info."
  default     = 9100
}
