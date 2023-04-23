#! /usr/bin/env bash
set -ex -o pipefail

cd "$(dirname "$BASH_SOURCE")"

export TF_PLUGIN_CACHE_DIR="${PWD}/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
mkdir -p tfstate

cd 1
    terraform init -backend-config='path=../tfstate/1.tfstate'
    terraform apply -auto-approve
    terraform output -raw kubeconfig >../kubeconfig.yaml
cd -

cd 2
    terraform init -backend-config='path=../tfstate/2.tfstate'
    terraform apply -auto-approve
    ./vault-unseal.sh
cd -
