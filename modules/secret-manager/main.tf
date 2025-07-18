/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  # distinct is needed to make the expanding function argument work
  iam = flatten([
    for secret, roles in var.iam : [
      for role, members in roles : {
        secret  = secret
        role    = role
        members = members
      }
    ]
  ])
  tag_bindings = merge([
    for k, v in var.secrets : {
      for kk, vv in v.tag_bindings : "${k}/${kk}" => {
        parent    = "//secretmanager.googleapis.com/projects/${coalesce(var.project_number, var.project_id)}/secrets/${google_secret_manager_secret.default[k].secret_id}"
        tag_value = vv
      }
    }
    if v.tag_bindings != null
  ]...)
  version_pairs = flatten([
    for secret, versions in var.versions : [
      for name, attrs in versions : merge(attrs, { name = name, secret = secret })
    ]
  ])
  version_keypairs = {
    for pair in local.version_pairs : "${pair.secret}:${pair.name}" => pair
  }
}

resource "google_secret_manager_secret" "default" {
  for_each            = var.secrets
  project             = var.project_id
  secret_id           = each.key
  labels              = lookup(var.labels, each.key, null)
  expire_time         = each.value.expire_time
  version_destroy_ttl = each.value.version_destroy_ttl

  dynamic "replication" {
    for_each = each.value.locations == null ? [""] : []
    content {
      auto {
        dynamic "customer_managed_encryption" {
          for_each = try(lookup(each.value.keys, "global", null) == null ? [] : [""], [])
          content {
            kms_key_name = each.value.keys["global"]
          }
        }
      }
    }
  }

  dynamic "replication" {
    for_each = each.value.locations == null ? [] : [""]
    content {
      user_managed {
        dynamic "replicas" {
          for_each = each.value.locations
          iterator = location
          content {
            location = location.value
            dynamic "customer_managed_encryption" {
              for_each = try(lookup(each.value.keys, location.value, null) == null ? [] : [""], [])
              content {
                kms_key_name = each.value.keys[location.value]
              }
            }
          }
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "default" {
  provider    = google-beta
  for_each    = local.version_keypairs
  secret      = google_secret_manager_secret.default[each.value.secret].id
  enabled     = each.value.enabled
  secret_data = each.value.data
}

resource "google_secret_manager_secret_iam_binding" "default" {
  provider = google-beta
  for_each = {
    for binding in local.iam : "${binding.secret}.${binding.role}" => binding
  }
  role      = each.value.role
  secret_id = google_secret_manager_secret.default[each.value.secret].id
  members   = each.value.members
}

resource "google_tags_tag_binding" "binding" {
  for_each  = local.tag_bindings
  parent    = each.value.parent
  tag_value = each.value.tag_value
}
