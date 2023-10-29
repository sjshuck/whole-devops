#! /usr/bin/env bash
set -ex -o pipefail

cd "$(dirname "$BASH_SOURCE")"

export TF_PLUGIN_CACHE_DIR="${PWD}/.terraform.d/plugin-cache"

for d in 2 1; do
    cd "$d"
        terraform init -backend-config="path=../tfstate/${d}.tfstate"
        terraform destroy -auto-approve || true # FIXME
    cd -
done

: 'If block storage lingers for 10 seconds, force-delete it'
for (( i = 0; i < 10; i++ )); do
    blocks="$(../vultr-api blocks | jq '.blocks[] | .id' -r)"
    if ! [[ $blocks ]]; then
        break
    fi
    sleep 1
done
for block in $blocks; do
    ../vultr-api -X DELETE "blocks/${block}"
done
