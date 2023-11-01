#! /usr/bin/env bash
set -e -o pipefail

err="$(mktemp)"
trap 'rm "$err"' EXIT

time_to_wait=60
echo >&2 "Waiting ${time_to_wait} seconds for Kubernetes nodes to be ready..."

start_time="$(date +%s)"
while true; do
    sleep 2

    if ! not_ready_nodes="$(
        kubectl --kubeconfig ../kubeconfig.yaml get nodes 2>>"$err" | awk '
            {
                if ($2 == "NotReady") { nodes = nodes sep $1; sep = ", " }
            }

            END { print (nodes) }
        '
    )"; then
        echo >&2 "Coudn't connect"
    elif [[ $not_ready_nodes ]]; then
        echo >&2 "Not ready: ${not_ready_nodes}"
    else
        exit 0
    fi

    if (( $(date +%s) > start_time + time_to_wait )); then
        if [[ -s $err ]]; then
            echo >&2 "kubectl error(s):"
            uniq >&2 <"$err"
        fi
        exit 1
    fi
done
