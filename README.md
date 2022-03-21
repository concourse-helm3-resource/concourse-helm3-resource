# Helm Resource for Concourse

![CI Build](https://concourse.pubb-it.com/api/v1/teams/main/pipelines/concourse-helm3-resource/jobs/build-image-tag/badge)

Deploy [Helm Charts](https://github.com/helm/helm) from [Concourse](https://concourse-ci.org/).

Heavily based on the work of [`linkyard/concourse-helm-resource`][linkyard].

[linkyard]: https://github.com/linkyard/concourse-helm-resource

## Docker Image
You can pull the resource image from [`typositoire/concourse-helm3-resource`][dockerhub]. !["Dockerhub Pull Badge"](https://img.shields.io/docker/pulls/typositoire/concourse-helm3-resource.svg "Dockerhub Pull Badge")

[dockerhub]: https://hub.docker.com/repository/docker/typositoire/concourse-helm3-resource

### DEPRECATION OF DOCKER HUB

Starting with version 1.19.1, you can pull the resource from Github [`ghcr.io/typositoire/concourse-helm3-resource`][github packages]. Docker hub will eventually stop receiving new images.

[github packages]: https://github.com/Typositoire/concourse-helm3-resource/pkgs/container/concourse-helm3-resource

## Usage

```yaml
resource_types:
- name: helm
  type: docker-image
  source:
    repository: typositoire/concourse-helm3-resource
```

## Source Configuration

-   `cluster_url`: _Optional._ URL to Kubernetes Master API service. Do not set when using the `kubeconfig_path` parameter, otherwise required.
-   `cluster_ca`: _Optional._ Cluster CA certificate PEM, optionally Base64 encoded. (Required if `insecure_cluster` == false)
-   `insecure_cluster`: _Optional._ Skip TLS verification for cluster API. (Required if `cluster_ca` is nil)
-   `token`: _Optional._ Bearer token for Kubernetes.  This, `token_path` or `admin_key`/`admin_cert` are required if `cluster_url` is https.
-   `token_path`: _Optional._ Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
-   `admin_key`: _Optional._ Base64 encoded PEM. Required if `cluster_url` is https and no `token` or 'token_path' is provided.
-   `admin_cert`: _Optional._ Base64 encoded PEM. Required if `cluster_url` is https and no `token` or 'token_path' is provided.
-   `release`: _Optional._ Name of the release (not a file, a string). (Default: autogenerated by helm)
-   `namespace`: _Optional._ Kubernetes namespace the chart will be installed into. (Default: default)
-   `helm_history_max`: _Optional._ Limits the maximum number of revisions. (Default: 0 = no limit)
-   `repos`: _Optional._ Array of Helm repositories to initialize, each repository is defined as an object with properties `name`, `url` (required) username and password (optional).
-   `plugins`: _Optional._ Array of Helm plugins to install, each defined as an object with properties `url` (required), `version` (optional).
-   `stable_repo`: _Optional_ A `false` value will disable using a default Helm stable repo. Any other value will be used to Override default Helm stable repo URL <https://charts.helm.sh/stable>. Useful if running helm deploys without internet access.
-   `tracing_enabled`: _Optional._ Enable extremely verbose tracing for this resource. Useful when developing the resource itself. May allow secrets to be displayed. (Default: false)
-   `helm_setup_purge_all`: _Optional._ Uninstalls and purge every helm release. Use with extreme caution. (Default: false)

## Source options for Google Cloud

-   `gcloud_cluster_auth`: _Optional._ Set to true to use gcloud service account file for kubernetes cluster authentication.

-   `gcloud_service_account_key_file`: _Optional_ Manadatory if gcloud_cluster_auth is set to true. Pass gcloud service account json contents as value or a file path containing service_account json.

-   `gcloud_project_name`: _Optional_ Manadatory if gcloud_cluster_auth is set to true. Pass gcloud project name where cluster is installed.

-   `gcloud_k8s_cluster_name`: _Optional_ Manadatory if gcloud_cluster_auth is set to true. Pass gcloud cluster name.

-   `gcloud_k8s_zone`: _Optional_ Manadatory if gcloud_cluster_auth is set to true. Pass gcloud kubernetes cluster zone.

## Source options for DigitalOcean

-   `digitalocean.cluster_id` _Optional._ ClusterID on digitalocean to fetch kubeconfig.
-   `digitalocean.access_token` _Optionl._ Read Access Token to fetch kubeconfig.

## Behavior

### `check`: Check the release, not happy with dynamic releases.

### `in`: Not Supported

### `out`: Deploy a helm chart (V3 only)

Deploy an helm chart

#### Parameters

-   `chart`: _Required._ Either the file containing the helm chart to deploy (ends with .tgz), the path to a local directory containing the chart or the name of the chart from a repo (e.g. `stable/mysql`).
-   `namespace`: _Optional._ Either a file containing the name of the namespace or the name of the namespace. (Default: taken from source configuration).
-   `create_namespace`: _Optional._ Create the namespace if it doesn't exist (Default: false).
-   `release`: _Optional._ Either a file containing the name of the release or the name of the release. (Default: taken from source configuration).
-   `values`: _Optional._ File containing the values.yaml for the deployment. Supports setting multiple value files using an array.
-   `override_values`: _Optional._ Array of values that can override those defined in values.yaml. Each entry in
    the array is a map containing a key and a value or path. Value is set directly while path reads the contents of
    the file in that path. A `hide: true` parameter ensures that the value is not logged and instead replaced with `***HIDDEN***`.
    A `type: string` parameter makes sure Helm always treats the value as a string (uses the `--set-string` option to Helm; useful if the value varies
    and may look like a number, eg. if it's a Git commit hash).
    A `verbatim: true` parameter escapes backslashes so the value is passed as-is to the Helm chart (useful for `((credentials))`).
    The default behaviour of backslashes in `--set` is to quote the next character so `val\ue` is treated as `value` by Helm.
-   `token_path`: _Optional._ Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
-   `version`: _Optional_ Chart version to deploy, can be a file or a value. Only applies if `chart` is not a file.
-   `test`: _Optional._ Test the release instead of installing it. Requires the `release`. (Default: false)
-   `test_logs`: _Optional._ Display pod logs when running `test`. (Default: false)
-   `uninstall`: _Optional._ Uninstalls the release instead of installing it. Requires the `release`. (Default: false)
-   `delete_namespace`: _Optional._ Deletes the namespace after uninstall. Requires `uninstall` set to true and `namespace`. (Default: false)
-   `replace`: _Optional._ Replace uninstall release with same name. (Default: false)
-   `force`: _Optional._ Force resource update through uninstall/recreate if needed. (Default: false)
-   `devel`: _Optional._ Allow development versions of chart to be installed. This is useful when wanting to install pre-release
    charts (i.e. 1.0.2-rc1) without having to specify a version. (Default: false)
-   `debug`: _Optional._ Dry run the helm install with the debug flag which logs interpolated chart templates. (Default: false)
-   `check_is_ready`: _Optional._ Requires that `wait` is set to Default. Applies --wait without timeout. (Default: false)
-   `atomic`: _Optional._ This flag will cause failed installs to purge the release, and failed upgrades to rollback to the previous release. (Default: false)
-   `reuse_values`: _Optional._ When upgrading, reuse the last release's values. (Default: false)
-   `reset_values`: _Optional._ When upgrading, reset the values to the ones built into the chart. (Default: false)
-   `timeout`: _Optional._ This flag sets the max time to wait for any individual Kubernetes operation. (Default: 5m0s)
-   `wait`: _Optional._ Allows deploy task to sleep for X seconds before continuing to next task. Allows pods to restart and become stable, useful where dependency between pods exists. (Default: 0)
-   `kubeconfig`: _Optional._ String containing a kubeconfig. Overrides `kubeconfig_path` and source configuration for cluster, token, and admin config.
-   `kubeconfig_path`: _Optional._ File containing a kubeconfig. Overrides source configuration for cluster, token, and admin config.
-   `show_diff`: _Optional._ Show the diff that is applied if upgrading an existing successful release. (Default: false)
-   `skip_missing_values:` _Optional._ Missing values files are skipped if they are specified in the values but do not exist. (Default false)

## Example

### Out

Define the resource:

Generic

```yaml
resources:
- name: myapp-helm
  type: helm
  source:
    cluster_url: https://kube-master.domain.example
    cluster_ca: _base64 encoded CA pem_
    admin_key: _base64 encoded key pem_
    admin_cert: _base64 encoded certificate pem_
    repos:
      - name: some_repo
        url: https://somerepo.github.io/charts
```

DigitalOcean

```yaml
resources:
- name: myapp-helm
  type: helm
  source:
    digitalocean:
      cluster_id: XXXXXXXXXXXXXX
      access_token: XXXXXXXXXXX
    repos:
      - name: some_repo
        url: https://somerepo.github.io/charts
```

Google cloud
```yaml
resources:
- name: myapp-helm
  type: helm
  source:
    gcloud_cluster_auth: true
    gcloud_service_account_key_file: _plain service account json file_ or _path to json file
    gcloud_project_name: _project name_
    gcloud_k8s_cluster_name: _k8s cluster name_
    gcloud_k8s_zone: _k8s zone_
    repos:
      - name: some_repo
        url: https://somerepo.github.io/charts
```


Add to job:

```yaml
jobs:
  # ...
  plan:
  - put: myapp-helm
    params:
      chart: source-repo/chart-0.0.1.tgz
      values: source-repo/values.yaml
      override_values:
      - key: replicas
        value: 2
      - key: version
        path: version/number # Read value from version/number
      - key: secret
        value: ((my-top-secret-value)) # Pulled from a credentials backend like Vault
        hide: true # Hides value in output
      - key: image.tag
        path: version/image_tag # Read value from version/number
        type: string            # Make sure it's interpreted as a string by Helm (not a number)
```
