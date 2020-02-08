locals {
  domain_name = var.use_prefix ? join("", [var.domain_prefix, var.domain_name]) : var.domain_name
}

