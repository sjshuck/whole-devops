#! /usr/bin/env bash
set -e -o pipefail

time_to_wait=180
echo >&2 "Waiting ${time_to_wait} seconds for Kubernetes nodes to be ready..."

start_time="$(date +%s)"
while true; do
    sleep 5

    if ! not_ready_nodes="$(
        kubectl --kubeconfig ../kubeconfig.yaml get nodes 2>/dev/null | awk '
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
        exit 1
    fi
done
