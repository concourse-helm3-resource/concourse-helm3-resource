#!/bin/bash
set -e

if [ -f "$source/$namespace_overwrite" ]; then
  namespace=$(cat $source/$namespace_overwrite)
elif [ -n "$namespace_overwrite" ]; then
  namespace=$namespace
fi

setup_kubernetes() {
  payload=$1
  source=$2

  mkdir -p /root/.kube
  kubeconfig_path=$(jq -r '.params.kubeconfig_path // ""' < $payload)
  absolute_kubeconfig_path="${source}/${kubeconfig_path}"
  kubeconfig=$(jq -r '.params.kubeconfig // ""' < $payload)
  if [ ! -z "$kubeconfig" ]; then
    echo "$kubeconfig" > /root/.kube/config
    chmod 600 /root/.kube/config
  elif [ -f "$absolute_kubeconfig_path" ]; then
    cp "$absolute_kubeconfig_path" "/root/.kube/config"
  else
    # Setup kubectl
    cluster_url=$(jq -r '.source.cluster_url // ""' < $payload)
    if [ -z "$cluster_url" ]; then
      echo "invalid payload (missing cluster_url)"
      exit 1
    fi
    if [[ "$cluster_url" =~ https.* ]]; then
      insecure_cluster=$(jq -r '.source.insecure_cluster // "false"' < $payload)
      cluster_ca=$(jq -r '.source.cluster_ca // ""' < $payload)
      cluster_ca_base64=$(jq -r '.source.cluster_ca_base64 // ""' < $payload)
      admin_key=$(jq -r '.source.admin_key // ""' < $payload)
      admin_cert=$(jq -r '.source.admin_cert // ""' < $payload)
      token=$(jq -r '.source.token // ""' < $payload)
      token_path=$(jq -r '.params.token_path // ""' < $payload)
      tls_server_name=$(jq -r '.source.tls_server_name // ""' < $payload)

      if [[ ! -z "$tls_server_name" ]]; then
          tls_server_name="--tls-server-name=$tls_server_name"
      fi

      if [ "$insecure_cluster" == "true" ]; then
        kubectl config set-cluster default --server=$cluster_url --insecure-skip-tls-verify=true $tls_server_name
      else
        ca_path="/root/.kube/ca.pem"
        if [[ ! -z "$cluster_ca_base64" ]]; then
          echo "$cluster_ca_base64" | base64 -d > $ca_path
        elif [[ ! -z "$cluster_ca" ]]; then
          echo "$cluster_ca" > $ca_path
        else
          echo "missing cluster_ca or cluster_ca_base64"
          exit 1
        fi
        
        kubectl config set-cluster default --server=$cluster_url --certificate-authority=$ca_path $tls_server_name
      fi

      if [ -f "$source/$token_path" ]; then
        kubectl config set-credentials admin --token=$(cat $source/$token_path)
      elif [ ! -z "$token" ]; then
        kubectl config set-credentials admin --token=$token
      else
        mkdir -p /root/.kube
        key_path="/root/.kube/key.pem"
        cert_path="/root/.kube/cert.pem"
        echo "$admin_key" | base64 -d > $key_path
        echo "$admin_cert" | base64 -d > $cert_path
        kubectl config set-credentials admin --client-certificate=$cert_path --client-key=$key_path
      fi

      kubectl config set-context default --cluster=default --user=admin
    else
      kubectl config set-cluster default --server=$cluster_url
      kubectl config set-context default --cluster=default
    fi

    kubectl config use-context default
  fi

  kubectl version
}

setup_aws_kubernetes() {
#  Need to pass in:
#  source.aws.region
#  source.aws.cluster_name
#  source.role **or** source.user
  payload=$1
  source=$2

  region=$(jq -r '.source.aws.region // ""' < $payload)
  cluster_name=$(jq -r '.source.aws.cluster_name // ""' < $payload)
  
  # only relevant to non-role based auth
  # no default value in order to support instance profile
  profile=$(jq -r '.source.aws.profile // ""' < $payload)
  profile_opt=""
  if [ -n "$profile" ]; then
    profile_opt="--profile ${profile}"
  fi

  if [ -z "$region" ] || [ -z "$cluster_name" ]; then
    echo "invalid payload for AWS EKS, please pass all required params"
    exit 1
  fi

  use_role_base_auth=$(jq -r '.source.aws|has("role")' < $payload)
  use_user_base_auth=$(jq -r '.source.aws|has("user")' < $payload)

  if [ "${use_role_base_auth}" = true ]; then
    # prioritize role based auth if both are specified.
    echo "proceed with assume-role to set up kubeconfig."
    role_arn=$(jq -r '.source.aws.role.arn // ""' < $payload)
    role_session_name=$(jq -r '.source.aws.role.session_name // ""' < $payload)

    echo "role_arn=${role_arn} role_session_name=${role_session_name}"
    if [ -z "${role_arn}" ]; then
      echo "invalid role arn for AWS EKS"
      exit 1
    fi
    # `aws eks update-kubeconfig --role-arn` only populates the `role-arn` to be used 
    # for `get-token`, and the role specified is not used for the initial describe cluster action
    # name-based discovery is limited to same account as whatever profile is being used.
    # additional functionality added to assume the same specified role in order to discover the cluster
    $(printf "env AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
    $(aws sts assume-role \
    --role-arn ${role_arn} \
    --role-session-name ${role_session_name:-EKSAssumeRoleSession} \
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
    --output text)) aws eks update-kubeconfig --region ${region} --name ${cluster_name} --role-arn ${role_arn}

    # assumed role credentail will **NOT** be persisted on the disk
  elif [ "${use_user_base_auth}" = true ]; then
    echo "proceed with user credentials to set up kubeconfig."

    access_key_id=$(jq -r '.source.aws.user.access_key_id // ""' < $payload)
    secret_access_key=$(jq -r '.source.aws.user.secret_access_key // ""' < $payload)
    role_arn=$(jq -r '.source.aws.user.role_arn // ""' < $payload)

    if [ -z "$access_key_id" ] || [ -z "$secret_access_key" ]; then
      echo "invalid user auth payload for AWS EKS, please pass all required params"
      exit 1
    fi

    # user credentials will be persisted on the disk under a specific profile
    # in order to call `aws eks get-token`
    mkdir -p ~/.aws
    echo "[${profile:-default}]
    aws_access_key_id=${access_key_id}
    aws_secret_access_key=${secret_access_key}
    region=${region}" > ~/.aws/credentials

    # If the role arn is provided, we will create a separate profile for the role.
    if [ -n "$role_arn" ]; then
      echo "[assume_role]
      role_arn=${role_arn}
      source_profile=${profile:-default}" >> ~/.aws/credentials

      aws eks update-kubeconfig --region ${region} --name ${cluster_name} --profile assume_role
    else
      aws eks update-kubeconfig --region ${region} --name ${cluster_name} ${profile_opt}
    fi

  else
    # defaults to use instance identity.
    echo "no role or user specified. Fallback to use identity of the instance e.g. instance profile) to set up kubeconfig"
    
    aws eks update-kubeconfig --region ${region} --name ${cluster_name} ${profile_opt}
  fi
  echo "done setting up kubeconfig for EKS"
}

setup_gcp_kubernetes() {
  payload=$1
  source=$2

  gcloud_service_account_key_file=$(jq -r '.source.gcloud_service_account_key_file // ""' < $payload)
  gcloud_workload_identity_enabled=$(jq -r '.source.gcloud_workload_identity_enabled // "false"' < $payload)
  gcloud_project_name=$(jq -r '.source.gcloud_project_name // ""' < $payload)
  gcloud_k8s_cluster_name=$(jq -r '.source.gcloud_k8s_cluster_name // ""' < $payload)
  gcloud_k8s_zone=$(jq -r '.source.gcloud_k8s_zone // ""' < $payload)

  if [ -z "$gcloud_project_name" ] || [ -z "$gcloud_k8s_cluster_name" ] || [ -z "$gcloud_k8s_zone" ]; then
    echo "invalid payload for gcloud auth, please pass all required params"
    exit 1
  fi

  if [ "$gcloud_workload_identity_enabled" == "false" ]; then
    if [ -z "$gcloud_service_account_key_file" ]; then
      echo "invalid payload for gcloud auth, please pass all required params"
      exit 1
    fi

    if [[ -f $gcloud_service_account_key_file ]]; then
      echo "service acccount $gcloud_service_account_key_file is passed as a file"
      gcloud_path="$gcloud_service_account_key_file"
    else
      echo "$gcloud_service_account_key_file" >> /gcloud.json
      gcloud_path="/gcloud.json"
    fi
    
    gcloud_service_account_name=($(cat $gcloud_path | jq -r ".client_email"))
    gcloud auth activate-service-account ${gcloud_service_account_name} --key-file $gcloud_path
    gcloud config set account ${gcloud_service_account_name}
  else
      echo "Workload Identity is enabled - no need to authenticate with a private key"
  fi
  
  gcloud config set project ${gcloud_project_name}
  gcloud container clusters get-credentials ${gcloud_k8s_cluster_name} --zone ${gcloud_k8s_zone}

}

setup_helm() {
  # $1 is the name of the payload file
  # $2 is the name of the source directory
  history_max=$(jq -r '.source.helm_history_max // "10"' < $1)

  helm_bin="helm"

  $helm_bin version

  # Are there any environment variables? If so, let's iterate over and them set it.
  env_vars=$(jq -c '.source.env_vars // {}' < "$1")
  if [ "$env_vars" != "{}" ]; then
    for key in $(echo "$env_vars" | jq -r 'keys[]'); do
      value=$(echo "$env_vars" | jq -r --arg key "$key" '.[$key]')
      export "$key"="$value"
    done
  fi

  helm_setup_purge_all=$(jq -r '.source.helm_setup_purge_all // "false"' <$1)
  if [ "$helm_setup_purge_all" = "true" ]; then
    local release
    for release in $(helm ls -aq --namespace $namespace )
    do
      helm uninstall "$release" --namespace $namespace
    done
  fi
}

wait_for_service_up() {
  SERVICE=$1
  TIMEOUT=$2
  if [ "$TIMEOUT" -le "0" ]; then
    echo "Service $SERVICE was not ready in time"
    exit 1
  fi
  RESULT=`kubectl get endpoints --namespace=$namespace $SERVICE -o jsonpath={.subsets[].addresses[].targetRef.name} 2> /dev/null || true`
  if [ -z "$RESULT" ]; then
    sleep 1
    wait_for_service_up $SERVICE $((--TIMEOUT))
  fi
}

setup_repos() {
  repos=$(jq -c '(try .source.repos[] catch [][])' < $1)
  plugins=$(jq -c '(try .source.plugins[] catch [][])' < $1)
  stable_repo=$(jq -r '.source.stable_repo // "https://charts.helm.sh/stable"' < $1 )

  local IFS=$'\n'

  if [ "$plugins" ]
  then
    for pl in $plugins; do
      plurl=$(echo $pl | jq -cr '.url')
      plversion=$(echo $pl | jq -cr '.version // ""')
      if [ -n "$plversion" ]; then
        $helm_bin plugin install $plurl --version $plversion
      else
        if [ -d $2/$plurl ]; then
          $helm_bin plugin install $2/$plurl
        else
          $helm_bin plugin install $plurl
        fi
      fi
    done
  fi

  if [ "$repos" ]
  then
    for r in $repos; do
      name=$(echo $r | jq -r '.name')
      url=$(echo $r | jq -r '.url')
      username=$(echo $r | jq -r '.username // ""')
      password=$(echo $r | jq -r '.password // ""')

      echo Installing helm repository $name $url
      if [[ -n "$username" && -n "$password" ]]; then
        $helm_bin repo add $name $url --username $username --password $password
      else
        $helm_bin repo add $name $url
      fi
    done

    $helm_bin repo update
  fi

  if [ ! "$stable_repo" == "false" ]; then
    $helm_bin repo add stable $stable_repo
    $helm_bin repo update
  fi
}

setup_resource() {
  tracing_enabled=$(jq -r '.source.tracing_enabled // "false"' < $1)
  if [ "$tracing_enabled" = "true" ]; then
    set -x
  fi

  digitalocean=$(jq -r '.source.digitalocean // "false"' < $1)
  do_cluster_id=$(jq -r '.source.digitalocean.cluster_id // "false"' < $1)
  do_access_token=$(jq -r '.source.digitalocean.access_token // "false"' < $1)
  gcloud_cluster_auth=$(jq -r '.source.gcloud_cluster_auth // "false"' < $1)
  aws_cluster_auth=$(jq -r '.source|has("aws")' < $1)

  if [ "$do_cluster_id" != "false" ] && [ "$do_access_token" != "false" ]; then
    echo "Initializing digitalocean..."
    setup_doctl $1 $2
  elif [ "$gcloud_cluster_auth" = "true" ]; then
    echo "Initializing kubectl access using gcloud service account file"
    setup_gcp_kubernetes $1 $2
  elif [ "$aws_cluster_auth" = "true" ]; then
      echo "Initializing kubectl access using AWS credentials"
      setup_aws_kubernetes $1 $2
  else
    echo "Initializing kubectl using certificates"
    setup_kubernetes $1 $2
  fi

  echo "Initializing helm..."
  setup_helm $1 $2
}

setup_doctl() {
  doctl_token=$(jq -r '.source.digitalocean.access_token // ""' < $payload)
  doctl_cluster_id=$(jq -r '.source.digitalocean.cluster_id // ""' < $payload)
  doctl auth init -t $doctl_token

  doctl kubernetes cluster kubeconfig save $doctl_cluster_id
}
