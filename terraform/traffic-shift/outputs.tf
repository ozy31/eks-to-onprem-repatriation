output "load_balancer_id" {
  description = "ID of the Cloudflare load balancer."
  value       = cloudflare_load_balancer.this.id
}

output "pool_ids" {
  description = "Pool ID per site."
  value       = { for site, pool in cloudflare_load_balancer_pool.site : site => pool.id }
}

output "split" {
  description = "Current share of new sessions per site, in percent."
  value = {
    eks = 100 - var.dc1_traffic_percent
    dc1 = var.dc1_traffic_percent
  }
}
