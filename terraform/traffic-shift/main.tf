locals {
  name = replace(var.hostname, ".", "-")

  # EKS stays the fallback until the data centre takes all traffic.
  fallback_site = var.dc1_traffic_percent == 100 ? "dc1" : "eks"
}

resource "cloudflare_load_balancer_monitor" "ready" {
  account_id       = var.account_id
  description      = "${var.hostname} readiness"
  type             = "https"
  method           = "GET"
  path             = var.health_check_path
  expected_codes   = "200"
  follow_redirects = false
  interval         = 30
  timeout          = 5
  retries          = 2
  consecutive_down = 2
  consecutive_up   = 2

  header = {
    Host = [var.hostname]
  }
}

resource "cloudflare_load_balancer_pool" "site" {
  for_each = var.sites

  account_id         = var.account_id
  name               = "${local.name}-${each.key}"
  description        = "${var.hostname} at ${each.key}"
  monitor            = cloudflare_load_balancer_monitor.ready.id
  check_regions      = var.check_regions
  minimum_origins    = 1
  notification_email = var.notification_email

  origins = [
    for origin in each.value.origins : {
      name    = origin.name
      address = origin.address
      enabled = true
      weight  = 1
      header = {
        host = [var.hostname]
      }
    }
  ]
}

resource "cloudflare_load_balancer" "this" {
  zone_id     = var.zone_id
  name        = var.hostname
  description = "EKS -> dc1 migration: ${var.dc1_traffic_percent}% of new sessions to dc1"
  proxied     = true

  # Weighted split between the two pools.
  steering_policy = "random"
  random_steering = {
    default_weight = 0
    pool_weights = {
      (cloudflare_load_balancer_pool.site["eks"].id) = (100 - var.dc1_traffic_percent) / 100
      (cloudflare_load_balancer_pool.site["dc1"].id) = var.dc1_traffic_percent / 100
    }
  }

  # If a site's pool is unhealthy, its share goes to the other site.
  default_pools = [
    cloudflare_load_balancer_pool.site["eks"].id,
    cloudflare_load_balancer_pool.site["dc1"].id,
  ]
  fallback_pool = cloudflare_load_balancer_pool.site[local.fallback_site].id
  adaptive_routing = {
    failover_across_pools = true
  }

  # A user stays on one site for the session: a request that writes on one
  # site and reads on the other would see replication lag as a bug.
  session_affinity     = "cookie"
  session_affinity_ttl = 1800
  session_affinity_attributes = {
    samesite               = "Lax"
    secure                 = "Always"
    zero_downtime_failover = "temporary"
  }
}
