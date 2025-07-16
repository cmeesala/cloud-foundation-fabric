# Cloud Function Module (v2)

Cloud Function management, with support for IAM roles, optional bucket creation and bundle via GCS URI, local zip, or local source folder.

<!-- BEGIN TOC -->
- [TODO](#todo)
- [Examples](#examples)
  - [HTTP trigger](#http-trigger)
  - [PubSub and non-HTTP triggers](#pubsub-and-non-http-triggers)
  - [Controlling HTTP access](#controlling-http-access)
  - [GCS bucket creation](#gcs-bucket-creation)
  - [Service account management](#service-account-management)
  - [Custom bundle config](#custom-bundle-config)
  - [Private Cloud Build Pool](#private-cloud-build-pool)
  - [Multiple Cloud Functions within project](#multiple-cloud-functions-within-project)
  - [Mounting secrets from Secret Manager](#mounting-secrets-from-secret-manager)
- [Variables](#variables)
- [Outputs](#outputs)
- [Fixtures](#fixtures)
<!-- END TOC -->

## TODO

- [ ] add support for `source_repository`

## Examples

### HTTP trigger

This deploys a Cloud Function with an HTTP endpoint, using a pre-existing GCS bucket for deployment, setting the service account to the Cloud Function default one, and delegating access control to the containing project.

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest modules=1 resources=5 fixtures=fixtures/functions-default-sa-iam-grants.tf e2e
```

### PubSub and non-HTTP triggers

Other trigger types other than HTTP are configured via the `trigger_config` variable. This example shows a PubSub trigger via [Eventarc](https://cloud.google.com/eventarc/docs):

```hcl
module "trigger-service-account" {
  source     = "./fabric/modules/iam-service-account"
  project_id = var.project_id
  name       = "sa-cloudfunction"
  iam_project_roles = {
    (var.project_id) = [
      "roles/run.invoker"
    ]
  }
}

module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  trigger_config = {
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = module.pubsub.topic.id
    service_account_email = module.trigger-service-account.email
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest modules=3 resources=9 fixtures=fixtures/pubsub.tf,fixtures/functions-default-sa-iam-grants.tf e2e
```

Ensure that pubsub service identity (`service-[project number]@gcp-sa-pubsub.iam.gserviceaccount.com` has `roles/iam.serviceAccountTokenCreator`
as documented [here](https://cloud.google.com/eventarc/docs/roles-permissions#pubsub-topic).

### Controlling HTTP access

To allow anonymous access to the function, grant the `roles/run.invoker` role to the special `allUsers` identifier. Use specific identities (service accounts, groups, etc.) instead of `allUsers` to only allow selective access. The Cloud Run role needs to be used as explained in the [gcloud documentation](https://cloud.google.com/sdk/gcloud/reference/functions/add-invoker-policy-binding#DESCRIPTION).

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  iam = {
    "roles/run.invoker" = ["allUsers"]
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest fixtures=fixtures/functions-default-sa-iam-grants.tf inventory=iam.yaml e2e
```

### GCS bucket creation

You can have the module auto-create the GCS bucket used for deployment via the `bucket_config` variable. Setting `bucket_config.location` to `null` will also use the function region for GCS.

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  prefix      = var.prefix
  name        = "test-cf-http"
  bucket_name = var.bucket
  bucket_config = {
    force_destroy             = true
    lifecycle_delete_age_days = 1
  }
  bundle_config = {
    path = "assets/sample-function/"
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest fixtures=fixtures/functions-default-sa-iam-grants.tf inventory=bucket-creation.yaml e2e
```

### Service account management

To use a custom service account managed by the module, set `service_account_create` to `true` and leave `service_account` set to `null` value (default).

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  service_account_create = true
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest modules=1 resources=6 fixtures=fixtures/functions-default-sa-iam-grants.tf e2e
```

To use an externally managed service account, pass its email in `service_account` and leave `service_account_create` to `false` (the default).

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  service_account = var.service_account.email
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest modules=1 resources=5 fixtures=fixtures/functions-default-sa-iam-grants.tf e2e
```

### Custom bundle config

The Cloud Function bundle can be configured via the `bundle_config` variable. The only mandatory argument is `bundle_config.path` which can point to:

- a GCS URI of a ZIP archive
- a local path to a ZIP archive
- a local path to a source folder

When a GCS URI or a local zip file are used, a change in their names will trigger redeployment. When a local source folder is used a ZIP archive will be automatically generated and its internally derived checksum will drive redeployment. You can optionally control its name and exclusions via the attributes in `bundle_config.folder_options`.

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
    folder_options = {
      archive_path = "bundle.zip"
      excludes     = ["__pycache__"]
    }
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest modules=1 resources=5 fixtures=fixtures/functions-default-sa-iam-grants.tf e2e
```

### Private Cloud Build Pool

This deploys a Cloud Function with an HTTP endpoint, using a pre-existing GCS bucket for deployment using a pre existing private Cloud Build worker pool.

```hcl
module "cf-http" {
  source            = "./fabric/modules/cloud-function-v2"
  project_id        = var.project_id
  region            = var.regions.secondary
  name              = "test-cf-http"
  bucket_name       = var.bucket
  build_worker_pool = google_cloudbuild_worker_pool.pool.id
  bundle_config = {
    path = "assets/sample-function/"
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest modules=1 resources=6 fixtures=fixtures/functions-default-sa-iam-grants.tf,fixtures/cloudbuild-custom-pool.tf e2e
```

### Multiple Cloud Functions within project

When deploying multiple functions via local folders do not reuse `bundle_config.archive_path` between instances as the result is undefined. Default `archive_path` creates file in `/tmp` folder using project Id and function name to avoid name conflicts.

```hcl
module "cf-http-one" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http-one"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
}

module "cf-http-two" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http-two"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}
# tftest fixtures=fixtures/functions-default-sa-iam-grants.tf inventory=multiple_functions.yaml e2e
```

### Mounting secrets from Secret Manager

This provides the latest value of the secret `var_secret` as `VARIABLE_SECRET` environment variable and three values of `path_secret` mounted in filesystem:

- `/app/secret/ver1` contains version referenced by `module.secret-manager.version_versions["credentials:v1"]`

```hcl
module "cf-http" {
  source      = "./fabric/modules/cloud-function-v2"
  project_id  = var.project_id
  region      = var.region
  name        = "test-cf-http"
  bucket_name = var.bucket
  bundle_config = {
    path = "assets/sample-function/"
  }
  secrets = {
    VARIABLE_SECRET = {
      is_volume  = false
      project_id = var.project_id
      secret     = reverse(split("/", module.secret-manager.secrets["credentials"].name))[0]
      versions = [
        "latest"
      ]
    }
    "/app/secret" = {
      is_volume  = true
      project_id = var.project_id
      secret     = reverse(split("/", module.secret-manager.secrets["credentials"].name))[0]
      versions = [
        "${module.secret-manager.version_versions["credentials:v1"]}:ver1"
      ]
    }
  }
  depends_on = [
    google_project_iam_member.bucket_default_compute_account_grant,
  ]
}

# tftest fixtures=fixtures/secret-credentials.tf,fixtures/functions-default-sa-iam-grants.tf inventory=secrets.yaml e2e
```
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [bucket_name](variables.tf#L27) | Name of the bucket that will be used for the function code. It will be created with prefix prepended if bucket_config is not null. | <code>string</code> | ✓ |  |
| [bundle_config](variables.tf#L51) | Cloud function source. Path can point to a GCS object URI, or a local path. A local path to a zip archive will generate a GCS object using its basename, a folder will be zipped and the GCS object name inferred when not specified. | <code title="object&#40;&#123;&#10;  path &#61; string&#10;  folder_options &#61; optional&#40;object&#40;&#123;&#10;    archive_path &#61; optional&#40;string&#41;&#10;    excludes     &#61; optional&#40;list&#40;string&#41;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [name](variables.tf#L149) | Name used for cloud function and associated resources. | <code>string</code> | ✓ |  |
| [project_id](variables.tf#L164) | Project id used for all resources. | <code>string</code> | ✓ |  |
| [region](variables.tf#L169) | Region used for all resources. | <code>string</code> | ✓ |  |
| [bucket_config](variables.tf#L17) | Enable and configure auto-created bucket. Set fields to null to use defaults. | <code title="object&#40;&#123;&#10;  force_destroy             &#61; optional&#40;bool&#41;&#10;  lifecycle_delete_age_days &#61; optional&#40;number&#41;&#10;  location                  &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |
| [build_environment_variables](variables.tf#L33) | A set of key/value environment variable pairs available during build time. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [build_service_account](variables.tf#L39) | Build service account email. | <code>string</code> |  | <code>null</code> |
| [build_worker_pool](variables.tf#L45) | Build worker pool, in projects/<PROJECT-ID>/locations/<REGION>/workerPools/<POOL_NAME> format. | <code>string</code> |  | <code>null</code> |
| [description](variables.tf#L84) | Optional description. | <code>string</code> |  | <code>&#34;Terraform managed.&#34;</code> |
| [docker_repository_id](variables.tf#L90) | User managed repository created in Artifact Registry. | <code>string</code> |  | <code>null</code> |
| [environment_variables](variables.tf#L96) | Cloud function environment variables. | <code>map&#40;string&#41;</code> |  | <code title="&#123;&#10;  LOG_EXECUTION_ID &#61; &#34;true&#34;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [function_config](variables.tf#L104) | Cloud function configuration. Defaults to using main as entrypoint, 1 instance with 256MiB of memory, and 180 second timeout. | <code title="object&#40;&#123;&#10;  binary_authorization_policy &#61; optional&#40;string&#41;&#10;  entry_point                 &#61; optional&#40;string, &#34;main&#34;&#41;&#10;  instance_count              &#61; optional&#40;number, 1&#41;&#10;  memory_mb                   &#61; optional&#40;number, 256&#41; &#35; Memory in MB&#10;  cpu                         &#61; optional&#40;string, &#34;0.166&#34;&#41;&#10;  runtime                     &#61; optional&#40;string, &#34;python310&#34;&#41;&#10;  timeout_seconds             &#61; optional&#40;number, 180&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  entry_point     &#61; &#34;main&#34;&#10;  instance_count  &#61; 1&#10;  memory_mb       &#61; 256&#10;  cpu             &#61; &#34;0.166&#34;&#10;  runtime         &#61; &#34;python310&#34;&#10;  timeout_seconds &#61; 180&#10;&#125;">&#123;&#8230;&#125;</code> |
| [iam](variables.tf#L125) | IAM bindings for topic in {ROLE => [MEMBERS]} format. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [ingress_settings](variables.tf#L131) | Control traffic that reaches the cloud function. Allowed values are ALLOW_ALL, ALLOW_INTERNAL_AND_GCLB and ALLOW_INTERNAL_ONLY . | <code>string</code> |  | <code>null</code> |
| [kms_key](variables.tf#L137) | Resource name of a KMS crypto key (managed by the user) used to encrypt/decrypt function resources in key id format. If specified, you must also provide an artifact registry repository using the docker_repository_id field that was created with the same KMS crypto key. | <code>string</code> |  | <code>null</code> |
| [labels](variables.tf#L143) | Resource labels. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [prefix](variables.tf#L154) | Optional prefix used for resource names. | <code>string</code> |  | <code>null</code> |
| [secrets](variables.tf#L174) | Secret Manager secrets. Key is the variable name or mountpoint, volume versions are in version:path format. | <code title="map&#40;object&#40;&#123;&#10;  is_volume  &#61; bool&#10;  project_id &#61; string&#10;  secret     &#61; string&#10;  versions   &#61; list&#40;string&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [service_account](variables.tf#L186) | Service account email. Unused if service account is auto-created. | <code>string</code> |  | <code>null</code> |
| [service_account_create](variables.tf#L192) | Auto-create service account. | <code>bool</code> |  | <code>false</code> |
| [trigger_config](variables.tf#L198) | Function trigger configuration. Leave null for HTTP trigger. | <code title="object&#40;&#123;&#10;  event_type   &#61; string&#10;  pubsub_topic &#61; optional&#40;string&#41;&#10;  region       &#61; optional&#40;string&#41;&#10;  event_filters &#61; optional&#40;list&#40;object&#40;&#123;&#10;    attribute &#61; string&#10;    value     &#61; string&#10;    operator  &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;, &#91;&#93;&#41;&#10;  service_account_email  &#61; optional&#40;string&#41;&#10;  service_account_create &#61; optional&#40;bool, false&#41;&#10;  retry_policy           &#61; optional&#40;string, &#34;RETRY_POLICY_DO_NOT_RETRY&#34;&#41; &#35; default to avoid permadiff&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |
| [vpc_connector](variables.tf#L216) | VPC connector configuration. Set create to 'true' if a new connector needs to be created. | <code title="object&#40;&#123;&#10;  create          &#61; optional&#40;bool, false&#41;&#10;  name            &#61; optional&#40;string&#41;&#10;  egress_settings &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [vpc_connector_config](variables.tf#L227) | VPC connector network configuration. Must be provided if new VPC connector is being created. | <code title="object&#40;&#123;&#10;  ip_cidr_range &#61; string&#10;  network       &#61; string&#10;  instances &#61; optional&#40;object&#40;&#123;&#10;    max &#61; optional&#40;number&#41;&#10;    min &#61; optional&#40;number, 2&#41;&#10;  &#125;&#41;&#41;&#10;  throughput &#61; optional&#40;object&#40;&#123;&#10;    max &#61; optional&#40;number, 300&#41;&#10;    min &#61; optional&#40;number, 200&#41;&#10;  &#125;&#41;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [bucket](outputs.tf#L17) | Bucket resource (only if auto-created). |  |
| [bucket_name](outputs.tf#L24) | Bucket name. |  |
| [function](outputs.tf#L29) | Cloud function resources. |  |
| [function_name](outputs.tf#L34) | Cloud function name. |  |
| [id](outputs.tf#L39) | Fully qualified function id. |  |
| [invoke_command](outputs.tf#L44) | Command to invoke Cloud Run Function. |  |
| [service_account](outputs.tf#L53) | Service account resource. |  |
| [service_account_email](outputs.tf#L58) | Service account email. |  |
| [service_account_iam_email](outputs.tf#L63) | Service account email. |  |
| [trigger_service_account](outputs.tf#L71) | Service account resource. |  |
| [trigger_service_account_email](outputs.tf#L76) | Service account email. |  |
| [trigger_service_account_iam_email](outputs.tf#L81) | Service account email. |  |
| [uri](outputs.tf#L89) | Cloud function service uri. |  |
| [vpc_connector](outputs.tf#L94) | VPC connector resource if created. |  |

## Fixtures

- [cloudbuild-custom-pool.tf](../../tests/fixtures/cloudbuild-custom-pool.tf)
- [functions-default-sa-iam-grants.tf](../../tests/fixtures/functions-default-sa-iam-grants.tf)
- [pubsub.tf](../../tests/fixtures/pubsub.tf)
- [secret-credentials.tf](../../tests/fixtures/secret-credentials.tf)
<!-- END TFDOC -->

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket\_config | Enable and configure auto-created bucket. Set fields to null to use defaults. | <pre>object({<br>    force_destroy             = optional(bool)<br>    lifecycle_delete_age_days = optional(number)<br>    location                  = optional(string)<br>  })</pre> | `null` | no |
| bucket\_name | Name of the bucket that will be used for the function code. It will be created with prefix prepended if bucket\_config is not null. | `string` | n/a | yes |
| build\_environment\_variables | A set of key/value environment variable pairs available during build time. | `map(string)` | `{}` | no |
| build\_service\_account | Build service account email. | `string` | `null` | no |
| build\_worker\_pool | Build worker pool, in projects/<PROJECT-ID>/locations/<REGION>/workerPools/<POOL\_NAME> format. | `string` | `null` | no |
| bundle\_config | Cloud function source. Path can point to a GCS object URI, or a local path. A local path to a zip archive will generate a GCS object using its basename, a folder will be zipped and the GCS object name inferred when not specified. | <pre>object({<br>    path = string<br>    folder_options = optional(object({<br>      archive_path = optional(string)<br>      excludes     = optional(list(string))<br>    }), {})<br>  })</pre> | n/a | yes |
| description | Optional description. | `string` | `"Terraform managed."` | no |
| docker\_repository\_id | User managed repository created in Artifact Registry. | `string` | `null` | no |
| environment\_variables | Cloud function environment variables. | `map(string)` | <pre>{<br>  "LOG_EXECUTION_ID": "true"<br>}</pre> | no |
| function\_config | Cloud function configuration. Defaults to using main as entrypoint, 1 instance with 256MiB of memory, and 180 second timeout. | <pre>object({<br>    binary_authorization_policy = optional(string)<br>    entry_point                 = optional(string, "main")<br>    instance_count              = optional(number, 1)<br>    memory_mb                   = optional(number, 256) # Memory in MB<br>    cpu                         = optional(string, "0.166")<br>    runtime                     = optional(string, "python310")<br>    timeout_seconds             = optional(number, 180)<br>  })</pre> | <pre>{<br>  "cpu": "0.166",<br>  "entry_point": "main",<br>  "instance_count": 1,<br>  "memory_mb": 256,<br>  "runtime": "python310",<br>  "timeout_seconds": 180<br>}</pre> | no |
| iam | IAM bindings for topic in {ROLE => [MEMBERS]} format. | `map(list(string))` | `{}` | no |
| ingress\_settings | Control traffic that reaches the cloud function. Allowed values are ALLOW\_ALL, ALLOW\_INTERNAL\_AND\_GCLB and ALLOW\_INTERNAL\_ONLY . | `string` | `null` | no |
| kms\_key | Resource name of a KMS crypto key (managed by the user) used to encrypt/decrypt function resources in key id format. If specified, you must also provide an artifact registry repository using the docker\_repository\_id field that was created with the same KMS crypto key. | `string` | `null` | no |
| labels | Resource labels. | `map(string)` | `{}` | no |
| name | Name used for cloud function and associated resources. | `string` | n/a | yes |
| prefix | Optional prefix used for resource names. | `string` | `null` | no |
| project\_id | Project id used for all resources. | `string` | n/a | yes |
| region | Region used for all resources. | `string` | n/a | yes |
| secrets | Secret Manager secrets. Key is the variable name or mountpoint, volume versions are in version:path format. | <pre>map(object({<br>    is_volume  = bool<br>    project_id = string<br>    secret     = string<br>    versions   = list(string)<br>  }))</pre> | `{}` | no |
| service\_account | Service account email. Unused if service account is auto-created. | `string` | `null` | no |
| service\_account\_create | Auto-create service account. | `bool` | `false` | no |
| trigger\_config | Function trigger configuration. Leave null for HTTP trigger. | <pre>object({<br>    event_type   = string<br>    pubsub_topic = optional(string)<br>    region       = optional(string)<br>    event_filters = optional(list(object({<br>      attribute = string<br>      value     = string<br>      operator  = optional(string)<br>    })), [])<br>    service_account_email  = optional(string)<br>    service_account_create = optional(bool, false)<br>    retry_policy           = optional(string, "RETRY_POLICY_DO_NOT_RETRY") # default to avoid permadiff<br>  })</pre> | `null` | no |
| vpc\_connector | VPC connector configuration. Set create to 'true' if a new connector needs to be created. | <pre>object({<br>    create          = optional(bool, false)<br>    name            = optional(string)<br>    egress_settings = optional(string)<br>  })</pre> | `{}` | no |
| vpc\_connector\_config | VPC connector network configuration. Must be provided if new VPC connector is being created. | <pre>object({<br>    ip_cidr_range = string<br>    network       = string<br>    instances = optional(object({<br>      max = optional(number)<br>      min = optional(number, 2)<br>    }))<br>    throughput = optional(object({<br>      max = optional(number, 300)<br>      min = optional(number, 200)<br>    }))<br>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket | Bucket resource (only if auto-created). |
| bucket\_name | Bucket name. |
| function | Cloud function resources. |
| function\_name | Cloud function name. |
| id | Fully qualified function id. |
| invoke\_command | Command to invoke Cloud Run Function. |
| service\_account | Service account resource. |
| service\_account\_email | Service account email. |
| service\_account\_iam\_email | Service account email. |
| trigger\_service\_account | Service account resource. |
| trigger\_service\_account\_email | Service account email. |
| trigger\_service\_account\_iam\_email | Service account email. |
| uri | Cloud function service uri. |
| vpc\_connector | VPC connector resource if created. |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->