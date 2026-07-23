#!/usr/bin/env bash

set -euo pipefail

primary_admin_secret_name="${PRIMARY_ADMIN_SECRET_NAME:-sidb-primary-admin}"
primary_admin_secret_key="${PRIMARY_ADMIN_SECRET_KEY:-oracle_pwd}"
primary_client_wallet_secret="${PRIMARY_CLIENT_WALLET_SECRET:-}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi
if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required" >&2
  exit 1
fi

kind="${1:?kind required: sidb|sharding|rac}"
name="${2:?resource name required}"
namespace="${3:?namespace required}"
broker_name="${4:-${name}-dg}"

case "$kind" in
  sidb)
    resource="singleinstancedatabase"
    ;;
  sharding)
    resource="shardingdatabase"
    ;;
  rac)
    resource="racdatabase"
    ;;
  *)
    echo "unsupported kind: $kind" >&2
    exit 1
    ;;
esac

kubectl get "$resource" "$name" -n "$namespace" -o json \
| jq \
  --arg broker_name "$broker_name" \
  --arg namespace "$namespace" \
  --arg primary_admin_secret_name "$primary_admin_secret_name" \
  --arg primary_admin_secret_key "$primary_admin_secret_key" \
  --arg primary_client_wallet_secret "$primary_client_wallet_secret" '
  if (.status.dataguard.renderedBrokerSpec // null) == null then
    error("status.dataguard.renderedBrokerSpec is empty. Wait until the standby database is Healthy and Data Guard prerequisites are complete.")
  else
    .status.dataguard.renderedBrokerSpec as $r
    | ($r.spec.topology.defaults.adminSecretRef // null) as $defaults_admin_secret_ref
    | ($r.spec.topology.defaults.tcps.clientWalletSecret // "") as $defaults_client_wallet_secret
    | {
        apiVersion: "database.oracle.com/v4",
        kind: "DataguardBroker",
        metadata: {
          name: ($r.name // $broker_name),
          namespace: ($r.namespace // $namespace)
        },
        spec: (
          $r.spec
          | .topology.members |= map(
              if .role == "PRIMARY" then
                (
                  if (
                    ($primary_admin_secret_name != "")
                    and (
                      .adminSecretRef == null
                      or (.adminSecretRef.secretName // "") == ""
                      or (.adminSecretRef.secretName == "replace-with-external-admin-secret")
                    )
                  )
                  then . + {
                    adminSecretRef: {
                      secretName: $primary_admin_secret_name,
                      secretKey: $primary_admin_secret_key
                    }
                  }
                  else .
                  end
                )
                |
                (
                  if (
                    ($primary_client_wallet_secret != "")
                    and (.tcps != null)
                    and (
                      (.tcps.clientWalletSecret // "") == ""
                      or (.tcps.clientWalletSecret == "replace-with-primary-client-wallet-secret")
                      or (.tcps.clientWalletSecret == "replace-with-shared-client-wallet-secret")
                      or (.tcps.clientWalletSecret == $defaults_client_wallet_secret)
                    )
                  )
                  then . + {
                    tcps: (
                      .tcps + {
                        clientWalletSecret: $primary_client_wallet_secret
                      }
                    )
                  }
                  else .
                  end
                )
              else .
              end
            )
        )
      }
  end
' \
| ruby -rjson -ryaml -e 'puts YAML.dump(JSON.parse(STDIN.read))'
