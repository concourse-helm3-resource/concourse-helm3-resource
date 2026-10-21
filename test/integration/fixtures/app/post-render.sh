#!/bin/sh
# Post-render through kubectl's built-in kustomize: label everything and add a marker
# ConfigMap, so the tests can see the post-renderer ran.
set -e
dir=$(mktemp -d)
cat > "$dir/rendered.yaml"
cat > "$dir/marker.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: post-rendered
EOF
cat > "$dir/kustomization.yaml" <<EOF
resources:
  - rendered.yaml
  - marker.yaml
labels:
  - pairs:
      post-rendered: kustomize
EOF
kubectl kustomize "$dir"
rm -rf "$dir"
