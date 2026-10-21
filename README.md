# Helm Resource for Concourse

![CI Build](https://concourse.pubb-it.com/api/v1/teams/main/pipelines/concourse-helm3-resource/jobs/build-image-tag/badge)

Deploy [Helm Charts](https://github.com/helm/helm) from [Concourse](https://concourse-ci.org/).

Heavily based on the work of [`linkyard/concourse-helm-resource`](https://github.com/linkyard/concourse-helm-resource).

## IMPORTANT NOTES

- Version 2.0.0 ships Helm 4. See [Upgrading to 2.0.0](#upgrading-to-200) before bumping a pipeline.
- Version 1.25.0 expects `cluster_ca` in base64 format in a new parameter called `cluster_ca_base64`. `cluster_ca` can still be used if a plain certificate is passed.
- Version 1.21.0 to 1.24.2 seems to be broken for certain uses cases. See [Issue#83](https://github.com/Typositoire/concourse-helm3-resource/issues/83)
- Version 1.21.0 to 1.24.2 seems to be missing helm diff plugin due to the use of HELM_PLUGINS environment variable
  - HELM_PLUGINS was used as a build arg to store plugins list, which made the plugins be installed in a weird
    place. Since this was a build arg only, installing the plugin again at run time worked.
- Feel free to add to this list
- Most of those have been fixed with v1.25.0 available in GHCR only

## Docker Image

You can pull the resource image from [`typositoire/concourse-helm3-resource`][dockerhub]. !["Dockerhub Pull Badge"](https://img.shields.io/docker/pulls/typositoire/concourse-helm3-resource.svg "Dockerhub Pull Badge")

[dockerhub]: https://hub.docker.com/repository/docker/typositoire/concourse-helm3-resource

### DEPRECATION OF DOCKER HUB

Starting with version 1.25.0, can you can no longer pull this resource from Docker Hub.

Starting with version 1.19.1, you can pull the resource from GitHub [`ghcr.io/typositoire/concourse-helm3-resource`][github packages]. Docker hub will eventually stop receiving new images.

[github packages]: https://github.com/Typositoire/concourse-helm3-resource/pkgs/container/concourse-helm3-resource

## Usage

```yaml
resource_types:
- name: helm
  type: docker-image
  source:
    repository: ghcr.io/typositoire/concourse-helm3-resource
    tag: v2.0.0
```

## Upgrading to 2.0.0

2.0.0 moves the image from Helm 3.14 to Helm 4.3. Pin `tag` to a 1.x version to stay on Helm 3.

- **Server-side apply.** New installs use server-side apply. Releases created by Helm 3 keep
  client-side apply until you set `server_side: "true"`; after one such deploy, later deploys
  stay server-side by default. Keep `server_side: "true"` set anyway: if a 1.x image touches the
  release again, Helm 3 drops the record of the apply method and `auto` falls back to client-side. The Kubernetes API server then merges each object itself, which
  removes one round trip per object.
- **Field conflicts.** Under server-side apply, a deploy fails if it changes a field another
  manager owns, for example a replica count set by `kubectl scale`. Set `force_conflicts: true`
  to let Helm take those fields. Moving a Helm 3 release over does not need it: Helm 4 uses the
  same `helm` field manager.
- **Renamed params.** `atomic` is now `rollback_on_failure` and `force` is now `force_replace`.
  The old names still work and log a deprecation warning. `force_replace` needs client-side
  apply, so it sets `server_side: "false"` unless you pass it yourself.
- **Waiting.** `check_is_ready` and `wait_for_jobs` wait with Helm 4's `watcher` strategy
  (kstatus). Set `wait_strategy: legacy` to get Helm 3's readiness checks.
- **Stable repo.** `stable_repo` now defaults to `"false"`. The archived `stable` repo has a
  10 MB index that was downloaded several times on every put. Set `stable_repo` to its URL if
  a chart still depends on it.
- **Plugins.** Plugins are signature-verified by default, as in Helm 4. A release tarball needs
  `keyring` set to its signer's public key. A Git URL cannot be verified, so it fails until its
  entry sets `verify: false`. A local plugin directory needs no signature.
- **Post-renderers.** Helm 4 only runs post-renderers packaged as plugins. A `post_renderer`
  path to an executable in the chart still works: the resource wraps it in a plugin. Any other
  value is treated as the name of an installed postrenderer plugin.

## Source Configuration

-   `cluster_url`: _Optional._ URL to Kubernetes Master API service. Do not set when using the `kubeconfig_path` parameter, otherwise required.
-   `cluster_ca`: _Optional._ Cluster CA certificate PEM. (Required if `insecure_cluster` == false)
-   `cluster_ca_base64`: _Optional._ Cluster CA certificate PEM Base64 encoded. (Required if `insecure_cluster` == false)
-   `insecure_cluster`: _Optional._ Skip TLS verification for cluster API. (Required if `cluster_ca` is nil)
-   `token`: _Optional._ Bearer token for Kubernetes.  This, `token_path` or `admin_key`/`admin_cert` are required if `cluster_url` is https.
-   `token_path`: _Optional._ Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
-   `tls_server_name`: _Optional._ Server name to use for server certificate validation. If it is not provided, the hostname used to contact the server is used.
-   `admin_key`: _Optional._ Base64 encoded PEM. Required if `cluster_url` is https and no `token` or 'token_path' is provided.
-   `admin_cert`: _Optional._ Base64 encoded PEM. Required if `cluster_url` is https and no `token` or 'token_path' is provided.
-   `release`: _Optional._ Name of the release (not a file, a string). (Default: autogenerated by helm)
-   `namespace`: _Optional._ Kubernetes namespace the chart will be installed into. (Default: default)
-   `helm_history_max`: _Optional._ Limits the maximum number of revisions. Use 0 for no limit. (Default: 10)
-   `repos`: _Optional._ Array of Helm repositories to initialize, each repository is defined as an object with properties `name`, `url` (required) username and password (optional).
-   `plugins`: _Optional._ Array of Helm plugins to install on `put`, each an object with:
    - `url` (required): a release tarball URL, a Git URL, or a plugin directory relative to the put's working directory.
    - `version` (optional): version constraint passed to `helm plugin install --version`.
    - `verify` (optional): verify the plugin signature (Default: true). Git URLs cannot be verified and need `false`.
    - `keyring` (optional): the signer's public key, armored or binary, as an `https://` URL or a file relative to the put's working directory. Required to verify a release tarball.

    ```yaml
    plugins:
    - url: https://github.com/databus23/helm-diff/releases/download/v3.15.15/diff-3.15.15-linux-amd64.tgz
      keyring: https://github.com/databus23.gpg
    - url: https://github.com/example/helm-foo
      version: v1.2.0
      verify: false
    - url: git-repo/plugins/my-plugin
    ```
-   `stable_repo`: _Optional_ URL of a Helm stable repo to add as `stable`, e.g. <https://charts.helm.sh/stable>. (Default: `"false"`, no stable repo)
-   `tracing_enabled`: _Optional._ Enable extremely verbose tracing for this resource. Useful when developing the resource itself. May allow secrets to be displayed. (Default: false)
-   `helm_setup_purge_all`: _Optional._ Uninstalls and purge every helm release. Use with extreme caution. (Default: false)
  - `env_vars`: _Optional._ A key/value pair of environment variables that will be set before running the helm command. This is useful for using different Helm storage options.

## Source options for Google Cloud

-   `gcloud_cluster_auth`: _Optional._ Set to true to use gcloud service account file for kubernetes cluster authentication.

-   `gcloud_service_account_key_file`: _Optional_ Mandatory if `gcloud_cluster_auth` is set to true and `gcloud_workload_identity_enabled` is set to `false`. Pass gcloud service account json contents as value or a file path containing service_account json.

- `gcloud_workload_identity_enabled`: _Optional_ Mandatory if `gcloud_cluster_auth` is set to true and `gcloud_service_account_key_file` is not set. Workload identity must be enabled on the cluster. (Default: `false`)

-   `gcloud_project_name`: _Optional_ Mandatory if `gcloud_cluster_auth` is set to true. Pass gcloud project name where cluster is installed.

-   `gcloud_k8s_cluster_name`: _Optional_ Mandatory if `gcloud_cluster_auth` is set to true. Pass gcloud cluster name.

-   `gcloud_k8s_zone`: _Optional_ Mandatory if `gcloud_cluster_auth` is set to true. Pass gcloud kubernetes cluster zone.

## Source options for DigitalOcean

-   `digitalocean.cluster_id` _Optional._ ClusterID on digitalocean to fetch kubeconfig.
-   `digitalocean.access_token` _Optionl._ Read Access Token to fetch kubeconfig.

## Source options for AWS EKS

-   `aws.region` _Optional._ Region of the EKS cluster
-   `aws.cluster_name` _Optionl._ Name of the EKS cluster
-   `aws.profile` _Optional._ Name of the AWS profile to store/use credentials, defaults to `default`. Only used for non-role based authentication
-   `aws.role.arn` _Optional._ ARN of the role to be used for EKS authentication
-   `aws.role.session_name` _Optional._ Session name of the assume-role session
-   `aws.user.access_key_id` _Optional._ Access key id of the user credential used for EKS authentication
-   `aws.user.secret_access_key` _Optional._ Secret access key of the user credential used for EKS authentication
-   `aws.user.role_arn` _Optional._ If this is provided, we will use the user credentials to assume into the role

## Behavior

### `check`: Check the release, not happy with dynamic releases.

### `in`: Not Supported

### `out`: Deploy a helm chart

Deploy an helm chart

#### Parameters

-   `private_registry.ecr.region`: _Optional._ Region of ECR `helm` registry.
-   `private_registry.ecr.account_id`: _Optional._ AWS account id of ECR `helm` registry.
-   `private_registry.ecr.profile` _Optional._ Name of the AWS profile to store/use credentials, defaults to `default`. Only used for non-role based authentication.
-   `private_registry.ecr.role.arn`: _Optional._ AWS IAM role ARN to be used to authenticate with ECR `helm` registry.
-   `private_registry.ecr.role.session_name`: _Optional._ AWS assume role session name for authenticating with ECR `helm` registry.
-   `private_registry.ecr.user.access_key_id` _Optional._ Access key id of the user credential used for ECR `helm` registry authentication
-   `private_registry.ecr.user.secret_access_key` _Optional._ Secret access key of the user credential used for ECR `helm` registry authentication
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
    A `type: file` parameter makes Helm treats the `path` as file (uses the `--set-file` option to Helm). 
    A `verbatim: true` parameter escapes backslashes so the value is passed as-is to the Helm chart (useful for `((credentials))`).
    The default behaviour of backslashes in `--set` is to quote the next character so `val\ue` is treated as `value` by Helm.
-   `token_path`: _Optional._ Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
-   `version`: _Optional_ Chart version to deploy, can be a file or a value. Only applies if `chart` is not a file.
-   `test`: _Optional._ Test the release instead of installing it. Requires the `release`. (Default: false)
-   `test_logs`: _Optional._ Display pod logs when running `test`. (Default: false)
-   `uninstall`: _Optional._ Uninstalls the release instead of installing it. Requires the `release`. (Default: false)
-   `delete_namespace`: _Optional._ Deletes the namespace after uninstall. Requires `uninstall` set to true and `namespace`. (Default: false)
-   `replace`: _Optional._ Replace uninstall release with same name. (Default: false)
-   `force_replace`: _Optional._ Force resource updates by replacement. Requires client-side apply, so `server_side` defaults to `"false"` when this is set. (Default: false)
-   `force`: _Deprecated._ Alias for `force_replace`.
-   `server_side`: _Optional._ `"true"`, `"false"` or `"auto"`. Apply objects with server-side apply. `"auto"` uses whatever the release used last time. (Default: Helm's, which is `"auto"` on upgrade and server-side on a new install)
-   `force_conflicts`: _Optional._ With server-side apply, take ownership of fields another field manager owns instead of failing. (Default: false)
-   `devel`: _Optional._ Allow development versions of chart to be installed. This is useful when wanting to install pre-release
    charts (i.e. 1.0.2-rc1) without having to specify a version. (Default: false)
-   `debug`: _Optional._ Dry run the helm install with the debug flag which logs interpolated chart templates. (Default: false)
-   `check_is_ready`: _Optional._ Requires that `wait` is set to Default. Applies --wait without timeout. (Default: false)
-   `wait_for_jobs`: _Optional._ Requires that `wait` is set to Default. Applies --wait and --wait-for-jobs without timeout. (Default: false)
-   `wait_strategy`: _Optional._ How `check_is_ready` and `wait_for_jobs` wait: `watcher` or `legacy` (Helm 3 behaviour). (Default: watcher)
-   `rollback_on_failure`: _Optional._ Failed installs are uninstalled and failed upgrades roll back to the previous release. (Default: false)
-   `atomic`: _Deprecated._ Alias for `rollback_on_failure`.
-   `reuse_values`: _Optional._ When upgrading, reuse the last release's values. (Default: false)
-   `reset_values`: _Optional._ When upgrading, reset the values to the ones built into the chart. (Default: false)
-   `timeout`: _Optional._ This flag sets the max time to wait for any individual Kubernetes operation. (Default: 5m0s)
-   `wait`: _Optional._ Allows deploy task to sleep for X seconds before continuing to next task. Allows pods to restart and become stable, useful where dependency between pods exists. (Default: 0)
-   `kubeconfig`: _Optional._ String containing a kubeconfig. Overrides `kubeconfig_path` and source configuration for cluster, token, and admin config.
-   `kubeconfig_path`: _Optional._ File containing a kubeconfig. Overrides source configuration for cluster, token, and admin config.
-   `show_diff`: _Optional._ Show the diff that is applied if upgrading an existing successful release. (Default: false)
-   `diff_opts`: _Optional._ Additional options to be appended to `helm diff` command. (Default: "")
-   `post_renderer`: _Optional._ Path to an executable inside the chart directory, or the name of an installed postrenderer plugin, used to post-render the manifests for the upgrade and the diff.
-   `skip_missing_values:` _Optional._ Missing values files are skipped if they are specified in the values but do not exist.(Default false)

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
    env_vars:
      HELM_DRIVER: sql
      HELM_DRIVER_SQL_CONNECTION_STRING: postgresql://helm-postgres:5432/helm?user=helm&password=changeme
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

Amazon EKS using IAM role
```yaml
resources:
- name: myapp-helm
  type: helm
  source:
    aws:
      region: aws-region
      cluster_name: eks-cluster-name
      role:
        arn: arn:aws:iam::<aws_account_id>:role/<my_eks_role>
        session_name: EKSAssumeRoleSession
```

Amazon EKS using user
```yaml
resources:
- name: myapp-helm
  type: helm
  source:
    aws:
      region: aws-region
      cluster_name: eks-cluster-name
      profile: eks_user
      user:
        access_key_id: <access_key_id>
        secret_access_key: <secret_access_key>
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
      - key: configuration
        path: configuration/production.yaml # add path to --set-file helm option 
        type: file            # use --set-file helm option ( --set-file configuration=configuration/production.yaml )
  # ...
```

Deploying charts from ECR private `helm` registry using IAM role auth

```yaml
jobs:
  # ...
  plan:
  - put: myapp-helm
    params:
      private_registry:
        ecr:
          region: us-west-2
          account_id: "01234567890"
          role:
            arn: "arn:aws:iam::09876543210:role/ecr_read_only"
      # region and account_id of the OCI url need to match the configuration in private_registry.ecr
      chart: oci://01234567890.dkr.ecr.us-west-2.amazonaws.com/myapp-helm-repo
      version: 1.2.3-myapp-helm-version
      namespace: myapp
      # limitation: concourse uses EKS deploy role, which does not have permission to create namespace on EKS.
      # for services, namespaces need to be created by service-lifecycle
      # for addons, namespeces are created by terraform from infra repo
      create_namespace: false
      release: myapp
      values: source-repo/values.yaml
      override_values:
      - key: image.tag
        value: oldest
  # ...
```

Deploying charts from ECR private `helm` registry using user auth
```yaml
jobs:
  # ...
  plan:
  - put: myapp-helm
    params:
      private_registry:
        ecr:
          region: us-west-2
          account_id: "01234567890"
          profile: ecr_user
          user:
            access_key_id: <access_key_id>
            secret_access_key: <secret_access_key>
      # region and account_id of the OCI url need to match the configuration in private_registry.ecr
      chart: oci://01234567890.dkr.ecr.us-west-2.amazonaws.com/myapp-helm-repo
  # ...
```

If `helm` chart contains `lookup` function
```yaml
resources:
- name: myapp-helm
  type: helm
  source:
    env_vars:
      HELM_DIFF_USE_INSECURE_SERVER_SIDE_DRY_RUN: true
    #...
jobs:
  # ...
  plan:
  - put: myapp-helm
    params:
      chart: ...
      show_diff: true
      diff_opts: "--dry-run=server"
      # ...
  # ...
```
