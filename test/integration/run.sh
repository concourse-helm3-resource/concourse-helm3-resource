#!/bin/bash
# Integration tests: run the resource image's out and check scripts against k3s, Postgres
# and a local chart repository, all in Docker.
#
#   test/integration/run.sh            build the image and run every case
#   test/integration/run.sh postgres   run only the cases whose name matches "postgres"
#
# IMAGE=<tag>  test an existing image instead of building one
# KEEP=1       leave the containers running afterwards (prints how to clean up)
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILTER="${1:-}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.35.4-k3s1}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16-alpine}"
HELM3_IMAGE="${HELM3_IMAGE:-alpine/helm:3.14.4}"
HELM_DIFF_URL="https://github.com/databus23/helm-diff/releases/download/v3.15.15/diff-3.15.15-linux-amd64.tgz"
HELM_DIFF_KEY="https://github.com/databus23.gpg"

NET="helm-resource-it-$$"
K3S="$NET-k3s"
PG="$NET-postgres"
REPO="$NET-repo"
PG_URL="postgresql://postgres:helm@postgres:5432/helm?sslmode=disable"
WORK="$(mktemp -d)"
LOG="$WORK/last.log"
OUT="$WORK/last.out"
RESULTS=()

# ---------------------------------------------------------------------------- environment

cleanup() {
  if [ "${KEEP:-}" = "1" ]; then
    echo "Kept: docker rm -f $K3S $PG $REPO; docker network rm $NET; rm -rf $WORK"
    return
  fi
  docker rm -f "$K3S" "$PG" "$REPO" >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

setup() {
  if [ -z "${IMAGE:-}" ]; then
    IMAGE="concourse-helm3-resource:integration"
    echo "Building $IMAGE"
    docker build -q -t "$IMAGE" "$ROOT" >/dev/null || die "image build failed"
  fi

  cp -R "$ROOT/test/integration/fixtures" "$WORK/src"
  docker network create "$NET" >/dev/null || die "network create failed"

  echo "Starting k3s, Postgres and a chart repository"
  docker run -d --name "$K3S" --network "$NET" --network-alias k3s --privileged \
    "$K3S_IMAGE" server --disable traefik --disable metrics-server --tls-san k3s >/dev/null || die "k3s failed to start"
  docker run -d --name "$PG" --network "$NET" --network-alias postgres \
    -e POSTGRES_PASSWORD=helm -e POSTGRES_DB=helm "$POSTGRES_IMAGE" >/dev/null || die "postgres failed to start"

  # Two repositories serving the same "lib" chart: needs-a depends on /a, needs-b on /b.
  mkdir -p "$WORK/repo/a" "$WORK/repo/b"
  for r in a b; do
    helm4 package /src/lib -d "/repo/$r" >/dev/null && helm4 repo index "/repo/$r" --url "http://chart-repo:8080/$r" \
      || die "packaging the test chart repository failed"
  done
  docker run -d --name "$REPO" --network "$NET" --network-alias chart-repo -v "$WORK/repo:/srv:ro" \
    busybox:1.37 httpd -f -p 8080 -h /srv >/dev/null || die "chart repository failed to start"

  for _ in $(seq 1 90); do
    docker exec "$K3S" kubectl get serviceaccount default >/dev/null 2>&1 \
      && docker exec "$PG" pg_isready -q -U postgres >/dev/null 2>&1 && break
    sleep 2
  done
  docker exec "$K3S" kubectl get serviceaccount default >/dev/null 2>&1 || die "k3s did not become ready"
  docker exec "$K3S" cat /etc/rancher/k3s/k3s.yaml | sed 's#https://127.0.0.1:6443#https://k3s:6443#' > "$WORK/kubeconfig"
}

# ---------------------------------------------------------------------------- helpers

# resource <out|check> <params json> [source json]: stdout to $OUT, logs to $LOG
resource() {
  local payload src="${3:-}"
  [ -n "$src" ] || src='{}'
  payload=$(jq -n --rawfile kc "$WORK/kubeconfig" --argjson p "$2" --argjson s "$src" \
    '{source: ({namespace: "it", release: "app"} + $s),
      params: ({kubeconfig: $kc, chart: "app", create_namespace: true} + $p), version: {}}')
  echo "$payload" | docker run --rm -i --network "$NET" -v "$WORK/src:/src" \
    "$IMAGE" "/opt/resource/$1" /src > "$OUT" 2> "$LOG"
}

# Helm 4 from the resource image, and Helm 3 from upstream, against the test cluster.
# stdout is the command's output; stderr is appended to $LOG.
helm4() {
  docker run --rm --network "$NET" --entrypoint helm \
    -v "$WORK:/work" -v "$WORK/src:/src" -v "$WORK/repo:/repo" -e KUBECONFIG=/work/kubeconfig \
    ${HELM_ENV:-} "$IMAGE" "$@" 2>> "$LOG"
}
helm3() {
  docker run --rm --network "$NET" \
    -v "$WORK:/work" -v "$WORK/src:/src" -e KUBECONFIG=/work/kubeconfig \
    ${HELM_ENV:-} "$HELM3_IMAGE" "$@" 2>> "$LOG"
}
SQL_ENV="-e HELM_DRIVER=sql -e HELM_DRIVER_SQL_CONNECTION_STRING=$PG_URL"

kc() { docker exec "$K3S" kubectl "$@" 2>&1; }
psql_q() { docker exec "$PG" psql -U postgres -d helm -tAc "$1"; }

# managers <namespace> <deployment>: the field managers and operations on the object
managers() {
  kc -n "$1" get deploy "$2" -o jsonpath='{range .metadata.managedFields[*]}{.manager}/{.operation} {end}'
}
# apply_method <namespace> <release>: "ssa" or "csa" for the last deployed revision
apply_method() {
  helm4 get metadata "$2" -n "$1" -o json | jq -r '.applyMethod // "csa"'
}

ok() { [ "$1" = "$2" ] || { echo "expected '$2', got '$1'" >> "$LOG"; return 1; }; }
has() { grep -qE -e "$1" "$LOG" || { echo "expected log to match: $1" >> "$LOG"; return 1; }; }
lacks() { ! grep -qE -e "$1" "$LOG" || { echo "expected log not to match: $1" >> "$LOG"; return 1; }; }
revision() { jq -r 'if type == "array" then .[-1].revision else .version.revision end' < "$OUT"; }

run_case() {
  local group="$1" name="$2" fn="$3"
  if [ -n "$FILTER" ] && ! [[ "$group $name" =~ $FILTER ]]; then return; fi
  printf '%-14s %s ... ' "$group" "$name"
  : > "$LOG"; : > "$OUT"
  if "$fn"; then
    echo "pass"; RESULTS+=("pass|$group|$name")
  else
    echo "FAIL"; RESULTS+=("FAIL|$group|$name")
    sed 's/^/    | /' "$LOG" | tail -25
  fi
}

# ---------------------------------------------------------------------------- end to end

t_install() {
  resource out '{"post_renderer": "post-render.sh", "show_diff": true, "check_is_ready": true}' || return 1
  ok "$(revision)" 1 && has 'Release diff:' && has 'post-rendered' \
    && ok "$(kc -n it get cm post-rendered -o jsonpath='{.metadata.labels.post-rendered}')" kustomize \
    && [[ "$(managers it app)" == *helm/Apply* ]]
}
t_check() {
  resource check '{}' && ok "$(revision)" 1
}
t_stable_off() {
  resource out '{}' && lacks '"stable" has been added'
}
t_legacy_params() {
  resource out '{"atomic": true, "force": true}' \
    && has 'params.atomic is deprecated' && has 'params.force is deprecated' \
    && has '--rollback-on-failure' && has '--force-replace' && has '--server-side=false'
}
t_force_replace_ssa() {
  ! resource out '{"server_side": "true", "force_replace": true}' && has 'force_replace requires server_side'
}
t_debug() {
  local before; before=$(helm4 history app -n it -o json | jq 'length')
  resource out '{"debug": true}' && has '--dry-run=client' && has '^kind: Deployment' \
    && ok "$(helm4 history app -n it -o json | jq 'length')" "$before"
}
t_validation() {
  ! resource out '{"server_side": "yes"}' && has 'server_side must be' || return 1
  ! resource out '{"wait_strategy": "hookOnly"}' && has 'wait_strategy must be' || return 1
  ! resource out '{"server_side": "false", "force_conflicts": true}' && has 'force_conflicts requires'
}
t_helm3_migration() {
  helm3 upgrade legacy /src/app --install -n it --set replicaCount=1 > "$LOG" || return 1
  [[ "$(managers it legacy)" != *Apply* ]] || return 1
  resource out '{"server_side": "true", "override_values": [{"key": "replicaCount", "value": "2"}]}' '{"release": "legacy"}' \
    && ok "$(kc -n it get deploy legacy -o jsonpath='{.spec.replicas}')" 2 \
    && [[ "$(managers it legacy)" == *helm/Apply* ]]
}
t_conflict() {
  kc -n it scale deploy legacy --replicas=5 >/dev/null
  ! resource out '{"override_values": [{"key": "replicaCount", "value": "3"}]}' '{"release": "legacy"}' \
    && has 'conflict' && has 'kubectl'
}
t_force_conflicts() {
  resource out '{"force_conflicts": true, "override_values": [{"key": "replicaCount", "value": "3"}]}' '{"release": "legacy"}' \
    && ok "$(kc -n it get deploy legacy -o jsonpath='{.spec.replicas}')" 3 || return 1
  # The next deploy stays server-side under the default "auto"
  resource out '{"override_values": [{"key": "replicaCount", "value": "2"}]}' '{"release": "legacy"}' \
    && ok "$(apply_method it legacy)" ssa
}
t_dep_configured_repo() {
  resource out '{"chart": "needs-a"}' '{"release": "needs-a", "repos": [{"name": "a", "url": "http://chart-repo:8080/a"}]}' \
    && has '--skip-refresh' && lacks 'Retrying with a repository refresh' \
    && ok "$(grep -c 'Successfully got an update\|has been added' "$LOG")" 1
}
t_dep_unconfigured_repo() {
  resource out '{"chart": "needs-b"}' '{"release": "needs-b", "repos": [{"name": "a", "url": "http://chart-repo:8080/a"}]}' \
    && has 'Retrying with a repository refresh'
}
t_uninstall() {
  resource out '{"uninstall": true}' '{"release": "needs-a"}' \
    && ! helm4 status needs-a -n it >/dev/null
}

# ---------------------------------------------------------------------------- plugins

# plugin_install <plugins json>: run the resource's plugin setup inside the image
plugin_install() {
  jq -n --argjson pl "$1" '{source: {plugins: $pl}}' > "$WORK/plugins.json"
  docker run --rm -v "$WORK:/work" -v "$WORK/src:/src" "$IMAGE" bash -c '
    source /opt/resource/common.sh; helm_bin=helm
    helm plugin uninstall diff >/dev/null
    set -e; setup_repos /work/plugins.json /src; helm plugin list' > "$LOG" 2>&1
}
t_image_helm_diff() {
  docker run --rm "$IMAGE" helm plugin list > "$LOG" 2>&1 && has '^diff'
}
t_plugin_keyring_url() {
  plugin_install "[{\"url\": \"$HELM_DIFF_URL\", \"keyring\": \"$HELM_DIFF_KEY\"}]" && has '^diff'
}
t_plugin_keyring_file() {
  curl -fsSL "$HELM_DIFF_KEY" -o "$WORK/src/helm-diff.asc" || return 1
  plugin_install "[{\"url\": \"$HELM_DIFF_URL\", \"keyring\": \"helm-diff.asc\"}]" && has '^diff'
}
t_plugin_no_keyring() {
  ! plugin_install "[{\"url\": \"$HELM_DIFF_URL\"}]"
}
t_plugin_git_default() {
  ! plugin_install '[{"url": "https://github.com/databus23/helm-diff", "version": "v3.15.15"}]'
}
t_plugin_git_unverified() {
  plugin_install '[{"url": "https://github.com/databus23/helm-diff", "version": "v3.15.15", "verify": false}]' && has '^diff'
}
t_plugin_local_dir() {
  plugin_install '[{"url": "plugins/local-plugin"}]' && has '^local-plugin'
}

# ---------------------------------------------------------------------------- postgres

PG_SOURCE="{\"namespace\": \"pg\", \"release\": \"pg\", \"env_vars\": {\"HELM_DRIVER\": \"sql\", \"HELM_DRIVER_SQL_CONNECTION_STRING\": \"$PG_URL\"}}"
pg_out() { resource out "$1" "$PG_SOURCE"; }
pg_rows() { psql_q "select count(*) from releases_v1 where name = 'pg'"; }
# pg_dump adds a random \restrict token to every dump, so drop it before comparing
schema() { docker exec "$PG" pg_dump -U postgres -d helm --schema-only | grep -vE '^\\(un)?restrict '; }

t_pg_helm3_history() {
  HELM_ENV="$SQL_ENV" helm3 upgrade pg /src/app --install -n pg --create-namespace --set message=1 > "$LOG" || return 1
  HELM_ENV="$SQL_ENV" helm3 upgrade pg /src/app -n pg --set message=2 >> "$LOG" || return 1
  schema > "$WORK/schema-helm3.sql"
  ok "$(pg_rows)" 2
}
t_pg_upgrade() {
  pg_out '{"server_side": "true", "override_values": [{"key": "message", "value": "3"}]}' \
    && ok "$(revision)" 3 && ok "$(pg_rows)" 3 || return 1
  resource check '{}' "$PG_SOURCE" && ok "$(revision)" 3 || return 1
  schema | diff "$WORK/schema-helm3.sql" - >> "$LOG" \
    && ok "$(kc -n pg get secrets -l owner=helm -o name | wc -l | tr -d ' ')" 0
}
t_pg_helm3_rollback() {
  HELM_ENV="$SQL_ENV" helm3 upgrade pg /src/app -n pg --set message=4 > "$LOG" \
    && HELM_ENV="$SQL_ENV" helm3 rollback pg 3 -n pg >> "$LOG" \
    && ok "$(pg_rows)" 5
}
t_pg_auto_after_helm3() {
  # Helm 3 rewrote revision 3 without apply_method, so "auto" falls back to client-side.
  # This is the documented reason to keep server_side: "true" set.
  pg_out '{"override_values": [{"key": "message", "value": "6"}]}' \
    && ok "$(HELM_ENV="$SQL_ENV" apply_method pg pg)" csa
}
t_pg_explicit_ssa() {
  pg_out '{"server_side": "true", "override_values": [{"key": "message", "value": "7"}]}' \
    && ok "$(HELM_ENV="$SQL_ENV" apply_method pg pg)" ssa
}
t_pg_rollback_to_helm3() {
  HELM_ENV="$SQL_ENV" helm4 rollback pg 2 -n pg > "$LOG" \
    && ok "$(kc -n pg get cm pg -o jsonpath='{.data.message}')" 2
}
t_pg_history_max() {
  local src; src=$(jq -c '. + {helm_history_max: 3}' <<< "$PG_SOURCE")
  for i in 1 2 3; do
    resource out "{\"server_side\": \"true\", \"override_values\": [{\"key\": \"message\", \"value\": \"max$i\"}]}" "$src" || return 1
  done
  ok "$(pg_rows)" 3
}

# ---------------------------------------------------------------------------- run

for tool in docker jq curl; do command -v "$tool" >/dev/null || die "$tool is required"; done
setup

run_case e2e "install with post-renderer, diff, check_is_ready" t_install
run_case e2e "check returns the deployed revision" t_check
run_case e2e "stable repo is off by default" t_stable_off
run_case e2e "deprecated atomic and force still work" t_legacy_params
run_case e2e "force_replace with server_side true is rejected" t_force_replace_ssa
run_case e2e "debug renders without releasing" t_debug
run_case e2e "invalid params are rejected" t_validation
run_case e2e "Helm 3 release moves to server-side apply" t_helm3_migration
run_case e2e "conflict with another field manager fails" t_conflict
run_case e2e "force_conflicts takes the field back" t_force_conflicts
run_case e2e "dependency from a configured repo skips refresh" t_dep_configured_repo
run_case e2e "dependency from an unconfigured repo falls back" t_dep_unconfigured_repo
run_case e2e "uninstall removes the release" t_uninstall

run_case plugins "image ships a verified helm-diff" t_image_helm_diff
run_case plugins "tarball with keyring URL" t_plugin_keyring_url
run_case plugins "tarball with keyring file" t_plugin_keyring_file
run_case plugins "tarball without keyring fails" t_plugin_no_keyring
run_case plugins "Git URL fails by default" t_plugin_git_default
run_case plugins "Git URL with verify false" t_plugin_git_unverified
run_case plugins "local plugin directory" t_plugin_local_dir

run_case postgres "Helm 3 writes history" t_pg_helm3_history
run_case postgres "upgrade over Helm 3 history, schema unchanged" t_pg_upgrade
run_case postgres "Helm 3 upgrades and rolls back after Helm 4" t_pg_helm3_rollback
run_case postgres "auto is client-side after a Helm 3 rollback" t_pg_auto_after_helm3
run_case postgres "explicit server_side returns to server-side" t_pg_explicit_ssa
run_case postgres "Helm 4 rolls back to a Helm 3 revision" t_pg_rollback_to_helm3
run_case postgres "helm_history_max prunes rows" t_pg_history_max

echo
failed=0
for r in "${RESULTS[@]}"; do [[ "$r" == FAIL* ]] && failed=$((failed + 1)); done
echo "$((${#RESULTS[@]} - failed)) passed, $failed failed"
[ "$failed" -eq 0 ]
