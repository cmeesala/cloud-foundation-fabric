# GKE Standard cluster module

This module offers a way to create and manage Google Kubernetes Engine (GKE) [Standard clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode#why-standard). With its sensible default settings based on best practices and authors' experience as Google Cloud practitioners, the module accommodates for many common use cases out-of-the-box, without having to rely on verbose configuration.

> [!IMPORTANT]
> This module should be used together with the [`gke-nodepool`](../gke-nodepool/) module because the default node pool is deleted upon cluster creation by default.

<!-- BEGIN TOC -->
- [Cluster access configurations](#cluster-access-configurations)
  - [Private cluster with DNS endpoint enabled](#private-cluster-with-dns-endpoint-enabled)
  - [Public cluster](#public-cluster)
  - [Allowing access from Google Cloud services](#allowing-access-from-google-cloud-services)
- [Regional cluster](#regional-cluster)
- [Enable Dataplane V2](#enable-dataplane-v2)
- [Managing GKE logs](#managing-gke-logs)
- [Monitoring configuration](#monitoring-configuration)
- [Disable GKE logs or metrics collection](#disable-gke-logs-or-metrics-collection)
- [Cloud DNS](#cloud-dns)
- [Backup for GKE](#backup-for-gke)
- [Automatic creation of new secondary ranges](#automatic-creation-of-new-secondary-ranges)
- [Node auto-provisioning with GPUs and TPUs](#node-auto-provisioning-with-gpus-and-tpus)
  - [Disable PSC endpoint creation](#disable-psc-endpoint-creation)
- [Variables](#variables)
- [Outputs](#outputs)
<!-- END TOC -->

## Cluster access configurations

The `access_config` variable can be used to configure access to the control plane, and nodes public access. The following examples illustrate different possible configurations.

### Private cluster with DNS endpoint enabled

The default module configuration creates a cluster with private nodes, no public endpoint, and access via the DNS endpoint enabled. The default variable configuration is shown in comments.

Master authorized ranges can be set via the `access_config.ip_access.authorized_ranges` attribute.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  # access_config can be omitted if master authorized ranges are not needed
  access_config = {
    # dns_access = true
    ip_access = {
      authorized_ranges = {
        internal-vms = "10.0.0.0/8"
      }
    }
    # private_nodes = true
  }
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
  max_pods_per_node = 32
  labels = {
    environment = "dev"
  }
}
# tftest modules=1 resources=1 inventory=access-private.yaml
```

### Public cluster

To configure a public cluster, turn off `access_config.ip_access.disable_public_endpoint`. Nodes can be left as private or made public if needed, like in the example below. DNS endpoint is turned off here as it's probably redundant for a public cluster.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  access_config = {
    dns_access = false
    ip_access = {
      authorized_ranges = {
        "corporate proxy" = "8.8.8.8/32"
      }
      gcp_public_cidrs_access_enabled = false
      disable_public_endpoint         = false
    }
    private_nodes = false
  }
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
  max_pods_per_node = 32
  labels = {
    environment = "dev"
  }
}
# tftest modules=1 resources=1 inventory=access-public.yaml
```

### Allowing access from Google Cloud services

To allow access to your cluster from Google Cloud services (like Cloud Shell, Cloud Build, etc.) without needing to manually specify all Google Cloud IP ranges, you can use the `gcp_public_cidrs_access_enabled` parameter:

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  access_config = {
    dns_access = false
    ip_access = {
      authorized_ranges = {
        internal-vms = "10.0.0.0/8"
      }
      gcp_public_cidrs_access_enabled = true
      disable_public_endpoint         = false
    }
    private_nodes = false
  }
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
  max_pods_per_node = 32
  labels = {
    environment = "dev"
  }
}
# tftest modules=1 resources=1 inventory=access-google.yaml
```

## Regional cluster

Regional clusters are created by setting `location` to a GCP region and then configuring `node_locations`, as shown in the example below.

```hcl
module "cluster-1" {
  source         = "./fabric/modules/gke-cluster-standard"
  project_id     = "myproject"
  name           = "cluster-1"
  location       = "europe-west1"
  node_locations = ["europe-west1-b"]
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
  max_pods_per_node = 32
  labels = {
    environment = "dev"
  }
}
# tftest modules=1 resources=1 inventory=regional.yaml
```

## Enable Dataplane V2

This example shows how to [create a zonal GKE Cluster with Dataplane V2 enabled](https://cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2).

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-dataplane-v2"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {} # use default names "pods" and "services"
  }
  enable_features = {
    dataplane_v2          = true
    fqdn_network_policy   = true
    secret_manager_config = true
    workload_identity     = true
  }
  labels = {
    environment = "dev"
  }
}
# tftest modules=1 resources=1
```

## Managing GKE logs

This example shows you how to [control which logs are sent from your GKE cluster to Cloud Logging](https://cloud.google.com/stackdriver/docs/solutions/gke/installing).

When you create a new GKE cluster, [Cloud Operations for GKE](https://cloud.google.com/stackdriver/docs/solutions/gke) integration with Cloud Logging is enabled by default and [System logs](https://cloud.google.com/stackdriver/docs/solutions/gke/managing-logs#what_logs) are collected. You can enable collection of several other [types of logs](https://cloud.google.com/stackdriver/docs/solutions/gke/managing-logs#what_logs). The following example enables collection of *all* optional logs.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {}
  }
  logging_config = {
    enable_workloads_logs          = true
    enable_api_server_logs         = true
    enable_scheduler_logs          = true
    enable_controller_manager_logs = true
  }
}
# tftest modules=1 resources=1 inventory=logging-config-enable-all.yaml
```

## Monitoring configuration

This example shows how to [configure collection of Kubernetes control plane metrics](https://cloud.google.com/stackdriver/docs/solutions/gke/managing-metrics#enable-control-plane-metrics). These metrics are optional and are not collected by default.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {} # use default names "pods" and "services"
  }
  monitoring_config = {
    enable_api_server_metrics         = true
    enable_controller_manager_metrics = true
    enable_scheduler_metrics          = true
  }
}
# tftest modules=1 resources=1 inventory=monitoring-config-control-plane.yaml
```

The next example shows how to [configure collection of kube state metrics](https://cloud.google.com/stackdriver/docs/solutions/gke/managing-metrics#enable-ksm). These metrics are optional and are not collected by default.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {} # use default names "pods" and "services"
  }
  monitoring_config = {
    enable_cadvisor_metrics    = true
    enable_daemonset_metrics   = true
    enable_deployment_metrics  = true
    enable_hpa_metrics         = true
    enable_pod_metrics         = true
    enable_statefulset_metrics = true
    enable_storage_metrics     = true
    # Kube state metrics collection requires Google Cloud Managed Service for Prometheus,
    # which is enabled by default.
    # enable_managed_prometheus = true
  }
}
# tftest modules=1 resources=1 inventory=monitoring-config-kube-state.yaml
```

The *control plane metrics* and *kube state metrics* collection can be configured in a single `monitoring_config` block.

## Disable GKE logs or metrics collection

> [!WARNING]
> If you've disabled Cloud Logging or Cloud Monitoring, GKE customer support
> is offered on a best-effort basis and might require additional effort
> from your engineering team.

This example shows how to fully disable logs collection on a zonal GKE Standard cluster. This is not recommended.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {}
  }
  logging_config = {
    enable_system_logs = false
  }
}
# tftest modules=1 resources=1 inventory=logging-config-disable-all.yaml
```

The next example shows how to fully disable metrics collection on a zonal GKE Standard cluster. This is not recommended.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {}
  }
  monitoring_config = {
    enable_system_metrics     = false
    enable_managed_prometheus = false
  }
}
# tftest modules=1 resources=1 inventory=monitoring-config-disable-all.yaml
```

## Cloud DNS

This example shows how to [use Cloud DNS as a Kubernetes DNS provider](https://cloud.google.com/kubernetes-engine/docs/how-to/cloud-dns) for GKE Standard clusters.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = var.project_id
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {}
  }
  enable_features = {
    dns = {
      provider = "CLOUD_DNS"
      scope    = "CLUSTER_SCOPE"
      domain   = "gke.local"
    }
  }
}
# tftest modules=1 resources=1 inventory=dns.yaml
```

## Backup for GKE

> [!NOTE]
> Although Backup for GKE can be enabled as an add-on when configuring your GKE clusters, it is a separate service from GKE.

[Backup for GKE](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/concepts/backup-for-gke) is a service for backing up and restoring workloads in GKE clusters. It has two components:

- A [Google Cloud API](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/reference/rest) that serves as the control plane for the service.
- A GKE add-on (the [Backup for GKE agent](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/concepts/backup-for-gke#agent_overview)) that must be enabled in each cluster for which you wish to perform backup and restore operations.

This example shows how to [enable Backup for GKE on a new zonal GKE Standard cluster](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/how-to/install#enable_on_a_new_cluster_optional) and [plan a set of backups](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/how-to/backup-plan).

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = var.project_id
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network               = var.vpc.self_link
    subnetwork            = var.subnet.self_link
    secondary_range_names = {}
  }
  backup_configs = {
    enable_backup_agent = true
    backup_plans = {
      "backup-1" = {
        region   = "europe-west2"
        schedule = "0 9 * * 1"
        applications = {
          namespace-1 = ["app-1", "app-2"]
        }
      }
    }
  }
}
# tftest modules=1 resources=2 inventory=backup.yaml
```

## Automatic creation of new secondary ranges

You can use `var.vpc_config.secondary_range_blocks` to let GKE create new secondary ranges for the cluster. The example below reserves an available /14 block for pods and a /20 for services.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = var.project_id
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_blocks = {
      pods     = ""
      services = "/20" # can be an empty string as well
    }
  }
}
# tftest modules=1 resources=1
```

## Node auto-provisioning with GPUs and TPUs

You can use `var.cluster_autoscaling` block to configure node auto-provisioning for the GKE cluster. The example below configures limits for CPU, memory, GPUs and TPUs.


```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-standard"
  project_id = var.project_id
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_blocks = {
      pods     = ""
      services = "/20"
    }
  }
  cluster_autoscaling = {
    cpu_limits = {
      max = 48
    }
    mem_limits = {
      max = 182
    }
    # Can be GPUs or TPUs
    accelerator_resources = [
      {
        resource_type = "nvidia-l4"
        max           = 2
      },
      {
        resource_type = "tpu-v5-lite-podslice"
        max           = 2
      }
    ]
  }
}
# tftest modules=1 resources=1
```

### Disable PSC endpoint creation

To disable IP access to the GKE control plane and prevent PSC endpoint creation, set `var.access_config.ip_access` to `null` or omit the variable.

```hcl
module "cluster-1" {
  source     = "./fabric/modules/gke-cluster-autopilot"
  project_id = "myproject"
  name       = "cluster-1"
  location   = "europe-west1"
  access_config = {
    dns_access = true
  }
  vpc_config = {
    network    = var.vpc.self_link
    subnetwork = var.subnet.self_link
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
  labels = {
    environment = "dev"
  }
}
# tftest modules=1 resources=1 inventory=no-ip-access.yaml
```
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [location](variables.tf#L269) | Cluster zone or region. | <code>string</code> | ✓ |  |
| [name](variables.tf#L384) | Cluster name. | <code>string</code> | ✓ |  |
| [project_id](variables.tf#L435) | Cluster project id. | <code>string</code> | ✓ |  |
| [vpc_config](variables.tf#L446) | VPC-level configuration. | <code title="object&#40;&#123;&#10;  disable_default_snat &#61; optional&#40;bool&#41;&#10;  network              &#61; string&#10;  subnetwork           &#61; string&#10;  secondary_range_blocks &#61; optional&#40;object&#40;&#123;&#10;    pods     &#61; string&#10;    services &#61; string&#10;  &#125;&#41;&#41;&#10;  secondary_range_names &#61; optional&#40;object&#40;&#123;&#10;    pods     &#61; optional&#40;string&#41;&#10;    services &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;  additional_ranges &#61; optional&#40;list&#40;string&#41;&#41;&#10;  stack_type        &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [access_config](variables.tf#L17) | Control plane endpoint and nodes access configurations. | <code title="object&#40;&#123;&#10;  dns_access &#61; optional&#40;bool, true&#41;&#10;  ip_access &#61; optional&#40;object&#40;&#123;&#10;    authorized_ranges                              &#61; optional&#40;map&#40;string&#41;&#41;&#10;    disable_public_endpoint                        &#61; optional&#40;bool&#41;&#10;    gcp_public_cidrs_access_enabled                &#61; optional&#40;bool&#41;&#10;    private_endpoint_authorized_ranges_enforcement &#61; optional&#40;bool&#41;&#10;    private_endpoint_config &#61; optional&#40;object&#40;&#123;&#10;      endpoint_subnetwork &#61; optional&#40;string&#41;&#10;      global_access       &#61; optional&#40;bool, true&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;&#10;  master_ipv4_cidr_block &#61; optional&#40;string&#41;&#10;  private_nodes          &#61; optional&#40;bool, true&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [backup_configs](variables.tf#L45) | Configuration for Backup for GKE. | <code title="object&#40;&#123;&#10;  enable_backup_agent &#61; optional&#40;bool, false&#41;&#10;  backup_plans &#61; optional&#40;map&#40;object&#40;&#123;&#10;    region                            &#61; string&#10;    applications                      &#61; optional&#40;map&#40;list&#40;string&#41;&#41;&#41;&#10;    encryption_key                    &#61; optional&#40;string&#41;&#10;    include_secrets                   &#61; optional&#40;bool, true&#41;&#10;    include_volume_data               &#61; optional&#40;bool, true&#41;&#10;    labels                            &#61; optional&#40;map&#40;string&#41;&#41;&#10;    namespaces                        &#61; optional&#40;list&#40;string&#41;&#41;&#10;    schedule                          &#61; optional&#40;string&#41;&#10;    retention_policy_days             &#61; optional&#40;number&#41;&#10;    retention_policy_lock             &#61; optional&#40;bool, false&#41;&#10;    retention_policy_delete_lock_days &#61; optional&#40;number&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [cluster_autoscaling](variables.tf#L67) | Enable and configure limits for Node Auto-Provisioning with Cluster Autoscaler. | <code title="object&#40;&#123;&#10;  enabled             &#61; optional&#40;bool, true&#41;&#10;  autoscaling_profile &#61; optional&#40;string, &#34;BALANCED&#34;&#41;&#10;  auto_provisioning_defaults &#61; optional&#40;object&#40;&#123;&#10;    boot_disk_kms_key &#61; optional&#40;string&#41;&#10;    disk_size         &#61; optional&#40;number&#41;&#10;    disk_type         &#61; optional&#40;string, &#34;pd-standard&#34;&#41;&#10;    image_type        &#61; optional&#40;string&#41;&#10;    oauth_scopes      &#61; optional&#40;list&#40;string&#41;&#41;&#10;    service_account   &#61; optional&#40;string&#41;&#10;    management &#61; optional&#40;object&#40;&#123;&#10;      auto_repair  &#61; optional&#40;bool, true&#41;&#10;      auto_upgrade &#61; optional&#40;bool, true&#41;&#10;    &#125;&#41;&#41;&#10;    shielded_instance_config &#61; optional&#40;object&#40;&#123;&#10;      integrity_monitoring &#61; optional&#40;bool, true&#41;&#10;      secure_boot          &#61; optional&#40;bool, false&#41;&#10;    &#125;&#41;&#41;&#10;    upgrade_settings &#61; optional&#40;object&#40;&#123;&#10;      blue_green &#61; optional&#40;object&#40;&#123;&#10;        node_pool_soak_duration &#61; optional&#40;string&#41;&#10;        standard_rollout_policy &#61; optional&#40;object&#40;&#123;&#10;          batch_percentage    &#61; optional&#40;number&#41;&#10;          batch_node_count    &#61; optional&#40;number&#41;&#10;          batch_soak_duration &#61; optional&#40;string&#41;&#10;        &#125;&#41;&#41;&#10;      &#125;&#41;&#41;&#10;      surge &#61; optional&#40;object&#40;&#123;&#10;        max         &#61; optional&#40;number&#41;&#10;        unavailable &#61; optional&#40;number&#41;&#10;      &#125;&#41;&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;&#10;  auto_provisioning_locations &#61; optional&#40;list&#40;string&#41;&#41;&#10;  cpu_limits &#61; optional&#40;object&#40;&#123;&#10;    min &#61; optional&#40;number, 0&#41;&#10;    max &#61; number&#10;  &#125;&#41;&#41;&#10;  mem_limits &#61; optional&#40;object&#40;&#123;&#10;    min &#61; optional&#40;number, 0&#41;&#10;    max &#61; number&#10;  &#125;&#41;&#41;&#10;  accelerator_resources &#61; optional&#40;list&#40;object&#40;&#123;&#10;    resource_type &#61; string&#10;    min           &#61; optional&#40;number, 0&#41;&#10;    max           &#61; number&#10;  &#125;&#41;&#41;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |
| [default_nodepool](variables.tf#L147) | Enable default nodepool. | <code title="object&#40;&#123;&#10;  remove_pool        &#61; optional&#40;bool, true&#41;&#10;  initial_node_count &#61; optional&#40;number, 1&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [deletion_protection](variables.tf#L165) | Whether or not to allow Terraform to destroy the cluster. Unless this field is set to false in Terraform state, a terraform destroy or terraform apply that would delete the cluster will fail. | <code>bool</code> |  | <code>true</code> |
| [description](variables.tf#L172) | Cluster description. | <code>string</code> |  | <code>null</code> |
| [enable_addons](variables.tf#L178) | Addons enabled in the cluster (true means enabled). | <code title="object&#40;&#123;&#10;  cloudrun                       &#61; optional&#40;bool, false&#41;&#10;  config_connector               &#61; optional&#40;bool, false&#41;&#10;  dns_cache                      &#61; optional&#40;bool, true&#41;&#10;  gce_persistent_disk_csi_driver &#61; optional&#40;bool, true&#41;&#10;  gcp_filestore_csi_driver       &#61; optional&#40;bool, true&#41;&#10;  gcs_fuse_csi_driver            &#61; optional&#40;bool, true&#41;&#10;  horizontal_pod_autoscaling     &#61; optional&#40;bool, true&#41;&#10;  http_load_balancing            &#61; optional&#40;bool, true&#41;&#10;  istio &#61; optional&#40;object&#40;&#123;&#10;    enable_tls &#61; bool&#10;  &#125;&#41;&#41;&#10;  kalm           &#61; optional&#40;bool, false&#41;&#10;  network_policy &#61; optional&#40;bool, false&#41;&#10;  stateful_ha    &#61; optional&#40;bool, false&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_features](variables.tf#L200) | Enable cluster-level features. Certain features allow configuration. | <code title="object&#40;&#123;&#10;  beta_apis                         &#61; optional&#40;list&#40;string&#41;&#41;&#10;  binary_authorization              &#61; optional&#40;bool, false&#41;&#10;  cilium_clusterwide_network_policy &#61; optional&#40;bool, false&#41;&#10;  cost_management                   &#61; optional&#40;bool, true&#41;&#10;  dns &#61; optional&#40;object&#40;&#123;&#10;    additive_vpc_scope_dns_domain &#61; optional&#40;string&#41;&#10;    provider                      &#61; optional&#40;string&#41;&#10;    scope                         &#61; optional&#40;string&#41;&#10;    domain                        &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;  multi_networking &#61; optional&#40;bool, false&#41;&#10;  database_encryption &#61; optional&#40;object&#40;&#123;&#10;    state    &#61; string&#10;    key_name &#61; string&#10;  &#125;&#41;&#41;&#10;  dataplane_v2          &#61; optional&#40;bool, true&#41;&#10;  fqdn_network_policy   &#61; optional&#40;bool, true&#41;&#10;  gateway_api           &#61; optional&#40;bool, false&#41;&#10;  groups_for_rbac       &#61; optional&#40;string&#41;&#10;  image_streaming       &#61; optional&#40;bool, false&#41;&#10;  intranode_visibility  &#61; optional&#40;bool, false&#41;&#10;  l4_ilb_subsetting     &#61; optional&#40;bool, false&#41;&#10;  mesh_certificates     &#61; optional&#40;bool&#41;&#10;  pod_security_policy   &#61; optional&#40;bool, false&#41;&#10;  secret_manager_config &#61; optional&#40;bool&#41;&#10;  security_posture_config &#61; optional&#40;object&#40;&#123;&#10;    mode               &#61; string&#10;    vulnerability_mode &#61; string&#10;  &#125;&#41;&#41;&#10;  resource_usage_export &#61; optional&#40;object&#40;&#123;&#10;    dataset                              &#61; string&#10;    enable_network_egress_metering       &#61; optional&#40;bool&#41;&#10;    enable_resource_consumption_metering &#61; optional&#40;bool&#41;&#10;  &#125;&#41;&#41;&#10;  service_external_ips &#61; optional&#40;bool, true&#41;&#10;  shielded_nodes       &#61; optional&#40;bool, false&#41;&#10;  tpu                  &#61; optional&#40;bool, false&#41;&#10;  upgrade_notifications &#61; optional&#40;object&#40;&#123;&#10;    topic_id &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;  vertical_pod_autoscaling &#61; optional&#40;bool, false&#41;&#10;  workload_identity        &#61; optional&#40;bool, true&#41;&#10;  enterprise_cluster       &#61; optional&#40;bool&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [issue_client_certificate](variables.tf#L256) | Enable issuing client certificate. | <code>bool</code> |  | <code>false</code> |
| [labels](variables.tf#L262) | Cluster resource labels. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [logging_config](variables.tf#L274) | Logging configuration. | <code title="object&#40;&#123;&#10;  enable_system_logs             &#61; optional&#40;bool, true&#41;&#10;  enable_workloads_logs          &#61; optional&#40;bool, false&#41;&#10;  enable_api_server_logs         &#61; optional&#40;bool, false&#41;&#10;  enable_scheduler_logs          &#61; optional&#40;bool, false&#41;&#10;  enable_controller_manager_logs &#61; optional&#40;bool, false&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [maintenance_config](variables.tf#L295) | Maintenance window configuration. | <code title="object&#40;&#123;&#10;  daily_window_start_time &#61; optional&#40;string&#41;&#10;  recurring_window &#61; optional&#40;object&#40;&#123;&#10;    start_time &#61; string&#10;    end_time   &#61; string&#10;    recurrence &#61; string&#10;  &#125;&#41;&#41;&#10;  maintenance_exclusions &#61; optional&#40;list&#40;object&#40;&#123;&#10;    name       &#61; string&#10;    start_time &#61; string&#10;    end_time   &#61; string&#10;    scope      &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  daily_window_start_time &#61; &#34;03:00&#34;&#10;  recurring_window        &#61; null&#10;  maintenance_exclusion   &#61; &#91;&#93;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [max_pods_per_node](variables.tf#L318) | Maximum number of pods per node in this cluster. | <code>number</code> |  | <code>110</code> |
| [min_master_version](variables.tf#L324) | Minimum version of the master, defaults to the version of the most recent official release. | <code>string</code> |  | <code>null</code> |
| [monitoring_config](variables.tf#L330) | Monitoring configuration. Google Cloud Managed Service for Prometheus is enabled by default. | <code title="object&#40;&#123;&#10;  enable_system_metrics &#61; optional&#40;bool, true&#41;&#10;  enable_api_server_metrics         &#61; optional&#40;bool, false&#41;&#10;  enable_controller_manager_metrics &#61; optional&#40;bool, false&#41;&#10;  enable_scheduler_metrics          &#61; optional&#40;bool, false&#41;&#10;  enable_daemonset_metrics   &#61; optional&#40;bool, false&#41;&#10;  enable_deployment_metrics  &#61; optional&#40;bool, false&#41;&#10;  enable_hpa_metrics         &#61; optional&#40;bool, false&#41;&#10;  enable_pod_metrics         &#61; optional&#40;bool, false&#41;&#10;  enable_statefulset_metrics &#61; optional&#40;bool, false&#41;&#10;  enable_storage_metrics     &#61; optional&#40;bool, false&#41;&#10;  enable_cadvisor_metrics    &#61; optional&#40;bool, false&#41;&#10;  enable_managed_prometheus &#61; optional&#40;bool, true&#41;&#10;  advanced_datapath_observability &#61; optional&#40;object&#40;&#123;&#10;    enable_metrics &#61; bool&#10;    enable_relay   &#61; bool&#10;  &#125;&#41;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [node_config](variables.tf#L389) | Node-level configuration. | <code title="object&#40;&#123;&#10;  boot_disk_kms_key             &#61; optional&#40;string&#41;&#10;  k8s_labels                    &#61; optional&#40;map&#40;string&#41;&#41;&#10;  labels                        &#61; optional&#40;map&#40;string&#41;&#41;&#10;  service_account               &#61; optional&#40;string&#41;&#10;  tags                          &#61; optional&#40;list&#40;string&#41;&#41;&#10;  workload_metadata_config_mode &#61; optional&#40;string&#41;&#10;  kubelet_readonly_port_enabled &#61; optional&#40;bool, true&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [node_locations](variables.tf#L411) | Zones in which the cluster's nodes are located. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#93;</code> |
| [node_pool_auto_config](variables.tf#L418) | Node pool configs that apply to auto-provisioned node pools in autopilot clusters and node auto-provisioning-enabled clusters. | <code title="object&#40;&#123;&#10;  cgroup_mode                   &#61; optional&#40;string&#41;&#10;  kubelet_readonly_port_enabled &#61; optional&#40;bool, true&#41;&#10;  network_tags                  &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  resource_manager_tags         &#61; optional&#40;map&#40;string&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [release_channel](variables.tf#L440) | Release channel for GKE upgrades. | <code>string</code> |  | <code>null</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [ca_certificate](outputs.tf#L17) | Public certificate of the cluster (base64-encoded). | ✓ |
| [cluster](outputs.tf#L25) | Cluster resource. | ✓ |
| [dns_endpoint](outputs.tf#L31) | Control plane DNS endpoint. |  |
| [endpoint](outputs.tf#L39) | Cluster endpoint. |  |
| [id](outputs.tf#L44) | FUlly qualified cluster id. |  |
| [location](outputs.tf#L49) | Cluster location. |  |
| [master_version](outputs.tf#L54) | Master version. |  |
| [name](outputs.tf#L59) | Cluster name. |  |
| [notifications](outputs.tf#L64) | GKE PubSub notifications topic. |  |
| [self_link](outputs.tf#L69) | Cluster self link. | ✓ |
| [workload_identity_pool](outputs.tf#L75) | Workload identity pool. |  |
<!-- END TFDOC -->
