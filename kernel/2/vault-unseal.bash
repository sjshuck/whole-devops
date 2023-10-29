#! /usr/bin/env bash
set -ex -o pipefail

cd "$(dirname "$BASH_SOURCE")"

function kubectl() {
    command kubectl --kubeconfig ../kubeconfig.yaml --namespace vault "$@"
}

function vault() {
    kubectl exec "$pod" -- sh -c \
        "VAULT_ADDR=http://localhost:8200 VAULT_FORMAT=json vault $* || true"
}

key_shares=1
key_threshold=1

for pod in $(kubectl get pods -o name); do
    status="$(vault status)"
    if ! $(jq <<<"$status" '.initialized'); then
        vault operator init \
            -key-shares="$key_shares" \
            -key-threshold="$key_threshold" \
            >../vault-init.json
    fi
    if $(jq <<<"$status" '.sealed'); then
        for key in $(
            jq <../vault-init.json '.unseal_keys_b64[]' -r |
                head -n "$key_threshold"
        ); do
            vault operator unseal "$key"
        done
    fi
done
