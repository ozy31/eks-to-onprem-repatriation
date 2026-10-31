variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID of the public hostname."
  type        = string
}

variable "hostname" {
  description = "Public hostname whose traffic is split between the sites, e.g. orders.example.com."
  type        = string
}

variable "sites" {
  description = <<-EOT
    Origins per site. Keys are site names; "eks" and "dc1" are expected.
    Addresses are what Cloudflare connects to (ALB hostname, data centre VIP);
    the Host header is always the public hostname, so both sites route the
    request the same way.
  EOT
  type = map(object({
    origins = list(object({
      name    = string
      address = string
    }))
  }))

  validation {
    condition     = alltrue([for s in ["eks", "dc1"] : contains(keys(var.sites), s)])
    error_message = "sites must contain \"eks\" and \"dc1\"."
  }
}

variable "dc1_traffic_percent" {
  description = <<-EOT
    Share of new sessions sent to the data centre. The migration moves it in
    steps (0, 1, 5, 25, 50, 100) with a soak period between them; rolling
    back is setting it to the previous step.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.dc1_traffic_percent >= 0 && var.dc1_traffic_percent <= 100
    error_message = "dc1_traffic_percent must be between 0 and 100."
  }
}

variable "health_check_path" {
  description = "Readiness path checked on every origin."
  type        = string
  default     = "/ready"
}

variable "check_regions" {
  description = "Cloudflare regions the health checks run from."
  type        = list(string)
  default     = ["WEU", "EEU"]
}

variable "notification_email" {
  description = "Address notified when an origin or pool changes health."
  type        = string
  default     = null
}
