FROM --platform=linux/amd64 alpine/helm:4.3.1
# Helm supported version along with K8 version: https://helm.sh/docs/topics/version_skew/
# List of Helm images: https://hub.docker.com/r/alpine/helm/tags

LABEL maintainer="Yann David (@Typositoire) <davidyann88@gmail>"

# Versions for gcloud, kubectl, doctl, awscli
# K8 versions: https://kubernetes.io/releases/
ARG KUBERNETES_VERSION=1.35.9
ARG GCLOUD_VERSION=590.0.0
ARG DOCTL_VERSION=1.57.0
ARG AWSCLI_VERSION=2.34.63-r0
ARG HELM_DIFF_VERSION=3.15.15


#gcloud path
ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

#install packages
RUN apk add --update --upgrade --no-cache jq bash curl git gettext libintl py-pip aws-cli=${AWSCLI_VERSION}

#install kubectl
RUN curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl

#install gcloud
RUN wget https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz \
    -O /tmp/google-cloud-sdk.tar.gz | bash

# For use with gke-gcloud-auth-plugin below
# see https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke
# for details
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

RUN mkdir -p /usr/local/gcloud \
    && tar -C /usr/local/gcloud -xvzf /tmp/google-cloud-sdk.tar.gz \
    && /usr/local/gcloud/google-cloud-sdk/install.sh -q \
    ## auth package is split out now, need explicit install
    ## --quiet disables interactive prompts
    && gcloud components install gke-gcloud-auth-plugin --quiet

#copy scripts
ADD assets /opt/resource

#install plugins
# Helm 4 verifies plugin signatures by default; helm-diff is installed from its VCS repo, which has no .prov to verify
RUN helm plugin install --verify=false --version v${HELM_DIFF_VERSION} https://github.com/databus23/helm-diff

#install kustomize
RUN curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash && \
  install kustomize /usr/local/bin/kustomize

#install doctl
RUN curl -sL -o /tmp/doctl.tar.gz https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz && \
  tar -C /usr/local/bin -zxvf /tmp/doctl.tar.gz && \
  chmod +x /usr/local/bin/doctl

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
