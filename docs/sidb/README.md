# Managing Oracle Single Instance Databases with Oracle Database Operator for Kubernetes

Oracle Database Operator for Kubernetes (`OraOperator`) includes the `SingleInstanceDatabase` (SIDB) controller for provisioning and operating Oracle single-instance databases on Kubernetes. This guide is organized around the current `database.oracle.com/v4` API and the v4 sample manifests in this repository.

Use this document when you want to:

- create a new single-instance database
- provision clone, standby, or True Cache databases
- configure Data Guard Broker, TCPS, external services, or custom scripts
- patch or resize a database
- enable Oracle REST Data Services (ORDS) and Oracle APEX

For related documents:

- Prerequisites: [`PREREQUISITES.md`](./PREREQUISITES.md)
- SIDB API migration notes: [`SIDB_V4_MIGRATION_FAQ.md`](./SIDB_V4_MIGRATION_FAQ.md)
- SIDB TCPS cert-manager single-script flow: [`TCPS_CERT_MANAGER_SCRIPT.md`](./tcps-cert-manager/README.md)

## Contents

- [Before You Begin](#before-you-begin)
- [Quick Start](#quick-start)
- [Scenario Guide](#scenario-guide)
- [SIDB v4 Resource Model](#sidb-v4-resource-model)
- [Status and Verification](#status-and-verification)
- [Common SIDB Workflows](#common-sidb-workflows)
- [Data Guard Workflows](#data-guard-workflows)
- [Oracle True Cache Workflows](#oracle-true-cache-workflows)
- [Networking, Security, and Runtime Options](#networking-security-and-runtime-options)
- [Storage, Lifecycle, and Maintenance](#storage-lifecycle-and-maintenance)
- [ORDS and APEX](#ords-and-apex)
- [Sample Catalog](#sample-catalog)

## Before You Begin

Complete the deployment prerequisites in [`PREREQUISITES.md`](./PREREQUISITES.md) before applying SIDB resources. That document is the primary place for:

- container registry access
- image pull secrets
- database admin password secrets
- storage preparation
- OpenShift notes
- optional TCPS, TDE, and advanced prerequisites

Oracle strongly recommends using the prerequisite document together with the current SIDB template:

- Template manifest: [`config/samples/sidb/singleinstancedatabase.yaml`](../../config/samples/sidb/singleinstancedatabase.yaml)

### Mandatory Resource Privileges

The SIDB controller requires the following Kubernetes resource privileges:

| Resource | Privileges |
| --- | --- |
| Pods | `create delete get list patch update watch` |
| Containers | `create delete get list patch update watch` |
| PersistentVolumeClaims | `create delete get list patch update watch` |
| Services | `create delete get list patch update watch` |
| Secrets | `create delete get list patch update watch` |
| Events | `create patch` |

For access management, see [`../../README.md`](../../README.md).

### Optional Resource Privileges

Some functionality requires additional RBAC:

| Functionality | Resource | Privileges |
| --- | --- | --- |
| NodePort service connect strings | Nodes | `list watch` |
| Storage expansion for block volumes | StorageClasses | `get list watch` |
| Custom scripts execution | PersistentVolumes | `get list watch` |

Apply the optional RBAC manifests when needed:

```sh
kubectl apply -f rbac/node-rbac.yaml
kubectl apply -f rbac/storage-class-rbac.yaml
kubectl apply -f rbac/persistent-volume-rbac.yaml
```

### OpenShift Security Context Constraints

If you deploy SIDB on OpenShift, create the required SCC and service account before creating the database. Use:

- [`config/samples/sidb/openshift_rbac.yaml`](../../config/samples/sidb/openshift_rbac.yaml)

Then set `spec.serviceAccountName` to the service account created for SIDB, for example `sidb-sa`.

## Quick Start

This is the fastest path for a new enterprise database using the v4 parameter layout:

1. Complete the prerequisites in [`PREREQUISITES.md`](./PREREQUISITES.md).
2. Create the admin password secret and the image pull secret.
3. Apply a SIDB manifest.
4. Verify status and connect.

Example:

```yaml
apiVersion: database.oracle.com/v4
kind: SingleInstanceDatabase
metadata:
  name: sidb-sample
  namespace: default
spec:
  sid: ORCL1
  edition: enterprise
  createAs: primary
  security:
    secrets:
      admin:
        secretName: db-admin-secret
        secretKey: oracle_pwd
        keepSecret: true
  charset: AL32UTF8
  pdbName: orclpdb1
  archiveLog: true
  image:
    pullFrom: container-registry.oracle.com/database/enterprise_ru:19
    pullSecrets: oracle-container-registry-secret
  persistence:
    oradata:
      size: 100Gi
      storageClass: oci-bv
      accessMode: ReadWriteOnce
  replicas: 1
```

Apply and verify:

```sh
kubectl apply -f sidb.yaml
kubectl get singleinstancedatabase sidb-sample
kubectl describe singleinstancedatabase sidb-sample
```

Use the sample manifest as a starting point:

- [`config/samples/sidb/singleinstancedatabase_create.yaml`](../../config/samples/sidb/singleinstancedatabase_create.yaml)

## Scenario Guide

Use this section as a quick entry point for the most common SIDB scenarios.

| Scenario | Where to start |
| --- | --- |
| New enterprise database | [Quick Start](#quick-start) and [Create a New Database](#create-a-new-database) |
| Prebuilt database | [Create a Prebuilt Database](#create-a-prebuilt-database) |
| Express edition | [Create Express, Free, or Free Lite Databases](#create-express-free-or-free-lite-databases) |
| Free edition | [Create Express, Free, or Free Lite Databases](#create-express-free-or-free-lite-databases) |
| Free Lite edition | [Create Express, Free, or Free Lite Databases](#create-express-free-or-free-lite-databases) |
| Clone database | [Clone a Database](#clone-a-database) |
| Standby database | [Create a Standby Database](#create-a-standby-database) |
| Data Guard Broker | [Data Guard Workflows](#data-guard-workflows) |
| TCPS-enabled database | [Enabling TCPS Connections](#enabling-tcps-connections) |
| True Cache in the same cluster | [True Cache in the Same Cluster](#true-cache-in-the-same-cluster) |
| True Cache with an external primary | [True Cache with an External Primary](#true-cache-with-an-external-primary) |
| ORDS and APEX | [ORDS and APEX](#ords-and-apex) |

## SIDB v4 Resource Model

The most important documentation change in v4 is the grouped parameter model. When authoring new manifests, prefer the v4 grouped layout described below.

### Key v4 Groups

| Area | v4 fields | Notes |
| --- | --- | --- |
| Admin credentials | `spec.security.secrets.admin` | Replaces the flat password-secret style for new manifests |
| Source database | `spec.primarySource` | Used for `clone`, `standby`, and `truecache` |
| True Cache | `spec.trueCache` | Covers blob generation and truecache-only options |
| TCPS | `spec.security.tcps` | Enables TCPS and TLS secret handling |
| External service | `spec.services.external` | Defines external TCP and TCPS service exposure |
| Storage | `spec.persistence.oradata` | Main datafiles volume definition |
| Resources | `spec.resources` | Standard Kubernetes resource requests and limits |

### Core SIDB Modes

The controller supports these primary `spec.createAs` values:

- `primary`
- `clone`
- `standby`
- `truecache`

### Source Database Reference

For `clone`, `standby`, and `truecache`, use `spec.primarySource` and set exactly one of:

- `primarySource.databaseRef`
- `primarySource.connectString`
- `primarySource.details`

Optional companion fields under `spec.primarySource`:

- `primarySource.dbName`
  Supplies the primary CDB `DB_NAME` only when it must be passed explicitly. Leave it unset when `primarySource.connectString` or `primarySource.databaseRef` already identifies the primary through the correct reachable service or SID. This is supported for `standby` and `truecache`.
- `primarySource.pdbName`
  Supplies the primary PDB name when the source is expressed through `primarySource.connectString`.

### Authoring Note

Use the grouped v4 fields from the main template when authoring new manifests:

- [`config/samples/sidb/singleinstancedatabase.yaml`](../../config/samples/sidb/singleinstancedatabase.yaml)

## Status and Verification

### List Databases

```sh
kubectl get singleinstancedatabases -o name
singleinstancedatabase.database.oracle.com/sidb-sample
```

### Quick Status

```sh
kubectl get singleinstancedatabase sidb-sample
NAME          EDITION      STATUS    ROLE      VERSION       CONNECT STR             TCPS CONNECT STR   OEM EXPRESS URL
sidb-sample   Enterprise   Healthy   PRIMARY   23.26.1.0.0   10.0.2.7:1521/ORCLPRD   Not enabled        Unavailable
```

Typical columns include edition, status, version, connect strings, and OEM Express URL.

### Detailed Status

```sh
kubectl describe singleinstancedatabase sidb-sample
```

Useful fields include:

- role
- SID
- PDB name
- release update
- replicas
- connect strings
- condition history

### JSONPath Examples

```sh
kubectl get singleinstancedatabase sidb-sample -o jsonpath='{.status.status}{"\n"}{.status.role}{"\n"}{.status.connectString}{"\n"}'
Healthy
PRIMARY
10.0.2.7:1521/ORCLPRD

kubectl get singleinstancedatabase sidb-sample -o jsonpath='{.status.tcpsConnectString}{"\n"}'
```

## Common SIDB Workflows

This section is task-oriented. Each workflow points to the recommended sample and highlights the main parameters to review.

### Create a New Database

Use when you want a fresh database instance initialized by the operator.

Primary sample:

- [`config/samples/sidb/singleinstancedatabase_create.yaml`](../../config/samples/sidb/singleinstancedatabase_create.yaml)

Key fields:

- `spec.sid`
- `spec.edition`
- `spec.createAs: primary`
- `spec.security.secrets.admin`
- `spec.charset`
- `spec.pdbName`
- `spec.archiveLog`
- `spec.image`
- `spec.persistence.oradata`
- `spec.replicas`

### Create a Prebuilt Database

Use when the image already contains a prebuilt database.

Sample:

- [`config/samples/sidb/singleinstancedatabase_prebuiltdb.yaml`](../../config/samples/sidb/singleinstancedatabase_prebuiltdb.yaml)

Key fields:

- `spec.image.prebuiltDB: true`
- prebuilt database image selection

### Create Express, Free, or Free Lite Databases

Use these edition-specific samples when you want lighter-weight database distributions.

Samples:

- [`config/samples/sidb/singleinstancedatabase_express.yaml`](../../config/samples/sidb/singleinstancedatabase_express.yaml)
- [`config/samples/sidb/singleinstancedatabase_free.yaml`](../../config/samples/sidb/singleinstancedatabase_free.yaml)
- [`config/samples/sidb/singleinstancedatabase_free-lite.yaml`](../../config/samples/sidb/singleinstancedatabase_free-lite.yaml)

Review:

- `spec.edition`
- image selection
- resource sizing
- storage sizing

### Connect to a Database

For application and operator-facing connections, use SIDB status:

```sh
kubectl get singleinstancedatabase sidb-sample -o jsonpath='{.status.connectString}{"\n"}'
10.0.2.7:1521/ORCLPRD
kubectl get singleinstancedatabase sidb-sample -o jsonpath='{.status.clusterConnectString}{"\n"}'
sidb-sample-ext.default:1521/ORCLPRD
kubectl get singleinstancedatabase sidb-sample -o jsonpath='{.status.tcpsConnectString}{"\n"}'
```

Use:

- `status.clusterConnectString` for in-cluster usage
- `status.connectString` for external TCP access
- `status.tcpsConnectString` for external TCPS access

### Clone a Database

Use when you want a new SIDB created from an existing primary database.

Sample:

- [`config/samples/sidb/singleinstancedatabase_clone.yaml`](../../config/samples/sidb/singleinstancedatabase_clone.yaml)

Key fields:

- `spec.createAs: clone`
- `spec.primarySource`
- `spec.security.secrets.admin`
- image compatible with the source database major version

### Create a Standby Database

Use when you want a physical standby SIDB for Data Guard.

Sample:

- [`config/samples/sidb/singleinstancedatabase_standby.yaml`](../../config/samples/sidb/singleinstancedatabase_standby.yaml)

Key fields:

- `spec.createAs: standby`
- `spec.primarySource`
- `spec.security.secrets.admin`
- storage and image compatibility with the source database
- for TDE-enabled primaries, `spec.security.secrets.tde` with both the TDE wallet password key and the standby wallet zip key

#### TDE Primary and Standby Wallet Setup

Use this flow when the primary SIDB has TDE enabled and the standby must be created from that primary. The operator mounts the exported primary wallet, and the database image imports it during standby bootstrap.

At a high level:

1. Create the primary TDE password Secret.
2. Create the primary SIDB with `spec.security.secrets.tde`.
3. Wait until the primary database is healthy.
4. Export the current primary wallet into a zip archive.
5. Create the standby TDE Secret with the wallet password and wallet archive.
6. Create the standby SIDB and reference that Secret.

Create the primary Secrets:

```sh
NS=shns

kubectl -n $NS create secret generic sidb-primary-tde-wallet \
  --from-literal=tde_wallet_pwd='<tde-wallet-password>'
```

Reference the Secrets from the primary SIDB:

```yaml
security:
  secrets:
    admin:
      secretName: sidb-primary-admin
      secretKey: oracle_pwd
      keepSecret: true
    tde:
      secretName: sidb-primary-tde-wallet
      secretKey: tde_wallet_pwd
```

After the primary is healthy, find the primary pod and effective `wallet_root`:

```sh
PRIMARY=sidb-primary
POD=$(kubectl -n $NS get pod -l app=$PRIMARY \
  -o jsonpath='{.items[0].metadata.name}')

kubectl -n $NS exec "$POD" -- bash -c 'sqlplus -s / as sysdba <<EOF
set heading off feedback off pages 0 verify off echo off
select value from v\$parameter where name = '\''wallet_root'\'';
exit
EOF'
```

Set `WALLET_ROOT` to the returned value. For example:

```sh
WALLET_ROOT=/opt/oracle/oradata/ORCL1/tdewallet
```

Create the wallet archive in the primary pod and copy it locally:

```sh
kubectl -n $NS exec "$POD" -- bash -c \
  "cd '$WALLET_ROOT' && rm -f /tmp/standby-wallet.zip && zip -qr /tmp/standby-wallet.zip tde"

kubectl -n $NS cp \
  "$POD:/tmp/standby-wallet.zip" \
  ./standby-wallet.zip
```

If the image does not contain `zip`, copy the wallet locally and create the archive:

```sh
kubectl -n $NS cp \
  "$POD:$WALLET_ROOT" \
  ./primary-wallet

(cd primary-wallet && zip -qr ../standby-wallet.zip tde)
```

Create the standby TDE Secret containing the password and wallet archive:

```sh
kubectl -n $NS create secret generic sidb-standby-tde-wallet \
  --from-literal=tde_wallet_pwd='<tde-wallet-password>' \
  --from-file=wallet.zip=./standby-wallet.zip
```

To update an existing standby wallet Secret:

```sh
kubectl -n $NS create secret generic sidb-standby-tde-wallet \
  --from-literal=tde_wallet_pwd='<tde-wallet-password>' \
  --from-file=wallet.zip=./standby-wallet.zip \
  --dry-run=client -o yaml |
kubectl apply -f -
```

Reference the primary from the standby SIDB and configure the TDE wallet Secret:

```yaml
security:
  secrets:
    admin:
      secretName: sidb-primary-admin
      secretKey: oracle_pwd
      keepSecret: true
    tde:
      secretName: sidb-standby-tde-wallet
      walletZipFileKey: wallet.zip
      walletRoot: /opt/oracle/oradata/dbconfig/ORCLS/tdewallet
```

Replace `ORCLS` with the standby SID.

The important standby TDE fields are:

* `secretName`: Secret containing the TDE wallet password and wallet archive.
* `walletZipFileKey`: Secret key containing the exported primary wallet archive.
* `walletRoot`: Persistent destination for the standby wallet under `/opt/oracle/oradata/dbconfig/<standby-sid>/tdewallet`.

During standby creation, the operator mounts `wallet.zip` as `standby-wallet.zip`. The database image validates and extracts the wallet, configures `wallet_root` and `tde_configuration`, and makes the wallet available during DBCA duplicate.

Always export the wallet from the current primary before creating the standby so the archive contains the active primary TDE keys.

### Patch a Database

Use when moving to a newer RU-compatible image.

Sample:

- [`config/samples/sidb/singleinstancedatabase_patch.yaml`](../../config/samples/sidb/singleinstancedatabase_patch.yaml)

What to change:

- `spec.image.pullFrom`
- optionally `spec.replicas` for lower-downtime patching

Verify:

```sh
kubectl describe singleinstancedatabase sidb-sample
```

Review status fields such as patched release update and related events.

## Data Guard Workflows

The SIDB controller and `DataguardBroker` controller work together for Data Guard workflows.

### Create the Standby SIDB

Create the standby first:

- [`config/samples/sidb/singleinstancedatabase_standby.yaml`](../../config/samples/sidb/singleinstancedatabase_standby.yaml)

If the primary uses TDE, complete [TDE Primary and Standby Wallet Setup](#tde-primary-and-standby-wallet-setup) before applying the standby manifest. The standby manifest must reference the Secret that contains both the TDE wallet password and the exported primary wallet zip.

Verify:

```sh
kubectl get singleinstancedatabase
kubectl get singleinstancedatabase standbydatabase-sample -o jsonpath='{.status.status}{"\n"}{.status.role}{"\n"}'
```

### Create the Data Guard Broker Configuration

Sample:

- [`config/samples/sidb/dataguardbroker.yaml`](../../config/samples/sidb/dataguardbroker.yaml)

For SIDB resources that publish a ready-to-use Data Guard Broker specification,
you can render the `DataguardBroker` manifest from the SIDB status:

```sh
./docs/sidb/script/dataguard/render-broker-from-status.sh \
  sidb sidb-primary shns sidb-standby-dg
```

The script requires `kubectl`, `jq`, and `yq`. It verifies that
`status.dataguard.readyForBroker` is true and that the SIDB has published a
rendered broker specification before producing the manifest. Apply the
rendered output after reviewing it.

Review:

- primary and standby references
- protection mode
- FSFO settings
- service exposure settings

Verify:

```sh
kubectl get dataguardbrokers
kubectl describe dataguardbroker sidb-standby-dg
```

### Perform Data Guard Operations

Use `spec.operations` on the `DataguardBroker` resource for manual switchover, failover, protection mode changes, and standby role conversions. Each operation uses a `requestId` token. The controller executes a request once for a given token and records the result in `status.operations`.

Before running an operation, verify the broker and database roles:

```sh
NS=<operator-watched-namespace>
DG=sidb-standby-dg

kubectl get dataguardbroker $DG -n $NS
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.primaryDatabase}{"\n"}{.status.standbyDatabases}{"\n"}{.status.protectionMode}{"\n"}{.status.status}{"\n"}'
kubectl get singleinstancedatabase -n $NS
```

Expected output before a normal switchover:

```text
PRIMDB
STBYDB
MaxPerformance
Ready
```

#### Switchover

Use switchover for planned role reversal when both primary and standby are healthy. Set `target` to the standby database that should become primary.

```sh
kubectl patch dataguardbroker $DG -n $NS --type merge \
  -p '{"spec":{"operations":{"switchover":{"target":"STBYDB","requestId":"switchover-001"}}}}'
```

Monitor the operation:

```sh
kubectl get dataguardbroker $DG -n $NS -w
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.operations.switchover.phase}{" "}{.status.operations.switchover.message}{"\n"}'
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.primaryDatabase}{"\n"}{.status.standbyDatabases}{"\n"}'
```

Expected output after the switchover completes:

```text
Succeeded switchover completed
STBYDB
PRIMDB
```

Verify the SIDB roles:

```sh
kubectl get singleinstancedatabase -n $NS \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.status,ROLE:.status.role,CONNECT:.status.connectString
```

Expected role change:

```text
sidb-primary    Healthy   PHYSICAL STANDBY   sidb-primary.<namespace>:1521/PRIMDB
sidb-standby    Healthy   PRIMARY            sidb-standby.<namespace>:1521/STBYDB
```

#### Failover

Use failover only when the primary database is unavailable or cannot be recovered through a normal switchover. Set `target` to the standby database that should become primary.

```sh
kubectl patch dataguardbroker $DG -n $NS --type merge \
  -p '{"spec":{"operations":{"failover":{"target":"STBYDB","requestId":"failover-001","force":true}}}}'
```

`force: true` requests an immediate failover. Use `force: false` or omit it when the broker can perform a normal failover.

Monitor the operation:

```sh
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.operations.failover.phase}{" "}{.status.operations.failover.message}{"\n"}{.status.primaryDatabase}{"\n"}{.status.standbyDatabases}{"\n"}'
```

Expected output:

```text
Succeeded failover completed
STBYDB
PRIMDB
```

After failover, inspect the old primary before reusing it. It may need reinstate, rebuild, or manual cleanup depending on the failure scenario.

#### Change Protection Mode

Patch `spec.operations.protectionMode` when you need to change the broker protection mode.

```sh
kubectl patch dataguardbroker $DG -n $NS --type merge \
  -p '{"spec":{"operations":{"protectionMode":{"mode":"MaxAvailability","requestId":"protection-mode-001"}}}}'
```

Monitor the operation:

```sh
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.operations.protectionMode.phase}{" "}{.status.operations.protectionMode.message}{"\n"}{.status.protectionMode}{"\n"}'
```

Expected output:

```text
Succeeded protection mode change completed
MaxAvailability
```

#### Convert Between Physical and Snapshot Standby

Use the explicit one-shot `roleConversion` operation to convert an existing standby database. This operation does not modify `spec.topology`, which remains immutable after reconciliation. Set `target` to either the topology member name or its `DB_UNIQUE_NAME`, and use a new `requestId` for every conversion request.

Before converting, verify the current live role:

```sh
kubectl get singleinstancedatabase -n $NS \
  -o custom-columns=NAME:.metadata.name,ROLE:.status.role,STATUS:.status.status
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.resolvedMembers}{"\n"}'
```

To convert a snapshot standby to a physical standby:

```sh
kubectl patch dataguardbroker $DG -n $NS --type merge \
  -p '{"spec":{"operations":{"roleConversion":{"target":"STBYDB","role":"PHYSICAL_STANDBY","requestId":"role-conversion-physical-001"}}}}'
```

To convert a physical standby to a snapshot standby:

```sh
kubectl patch dataguardbroker $DG -n $NS --type merge \
  -p '{"spec":{"operations":{"roleConversion":{"target":"STBYDB","role":"SNAPSHOT_STANDBY","requestId":"role-conversion-snapshot-001"}}}}'
```

Monitor the one-shot operation:

```sh
kubectl get dataguardbroker $DG -n $NS -w
kubectl get dataguardbroker $DG -n $NS \
  -o jsonpath='{.status.operations.roleConversion.phase}{" "}{.status.operations.roleConversion.message}{"\n"}'
kubectl get singleinstancedatabase -n $NS \
  -o custom-columns=NAME:.metadata.name,ROLE:.status.role,STATUS:.status.status
```

Expected successful result:

```text
Succeeded standby role conversion completed
```

The controller verifies the live broker role after issuing the DGMGRL conversion. The operation remains `Running` or pending until the requested role is reported. If it reaches `Failed`, correct the broker or database condition and retry with a new `requestId`; reusing a completed request ID will not execute the operation again.

Use a new `requestId` for each new switchover, failover, or protection mode request. If an operation fails and you want to retry after fixing the cause, patch the same operation with a new `requestId`.

### Enable Fast-Start Failover

Enable `spec.fastStartFailover` in the `DataguardBroker` resource.

Important:

- snapshot standby is not supported for FSFO
- all referenced databases must remain healthy and correctly configured

### Static Data Guard Connect String

The broker and SIDB status fields provide the current connect strings for automation and verification. Use:

```sh
kubectl get dataguardbroker sidb-standby-dg -o jsonpath='{.status.externalConnectString}{"\n"}{.status.clusterConnectString}{"\n"}'
```

### Patch Primary and Standby Databases

Patch the SIDB resources first, then verify the broker view:

```sh
kubectl get dataguardbroker sidb-standby-dg
kubectl get singleinstancedatabase
```

### Delete the Data Guard Configuration

Delete the `DataguardBroker` resource before deleting the standby database:

```sh
kubectl delete dataguardbroker sidb-standby-dg
kubectl delete singleinstancedatabase standbydatabase-sample
```

## Oracle True Cache Workflows

True Cache support is a major v4 workflow and should be documented as first-class SIDB functionality.

### Generate the True Cache Blob on the Primary Database

Use this when the operator should prepare the True Cache configuration blob from the primary database.

Start from this sample manifest:

- [`config/samples/sidb/singleinstancedatabase_create.yaml`](../../config/samples/sidb/singleinstancedatabase_create.yaml)

For a cross-cluster primary that also exposes an external endpoint and TCPS, use:

- [`config/samples/sidb/singleinstancedatabase_truecache_primary_tcps_peered.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache_primary_tcps_peered.yaml)

Use these fields:

- `metadata.name`
  This becomes the primary SIDB resource name and is later referenced from the True Cache manifest through `spec.primarySource.databaseRef`.
- `spec.sid`
  The Oracle SID for the primary database. Use only alphanumeric characters.
- `spec.edition: enterprise`
  Required for True Cache workflows.
- `spec.createAs: primary`
  Declares that this resource is the source primary database.
- `spec.pdbName`
  The PDB name used by the application and by the True Cache service mapping.
- `spec.archiveLog: true`
  Required so the operator can prepare the True Cache blob.
- `spec.security.secrets.admin`
  Points to the Kubernetes secret holding the SYS, SYSTEM, and PDB admin password input expected by the operator.
- `spec.security.secrets.tde`
  References the TDE wallet password secret used by the primary database for the True Cache workflow.
- `spec.image`
  Select an Oracle Database image compatible with your environment and operator support matrix.
- `spec.persistence.oradata`
  Defines the main storage volume for the primary database.
- `spec.trueCache.generateBlob: true`
  Tells the operator to generate the True Cache bootstrap blob file on the primary when it is missing.
- `spec.trueCache.createConfigMap: true`
  Tells the operator to create the True Cache blob ConfigMap when it is missing, and refresh it only after a new blob is generated.
- `spec.trueCache.generatePath`
  Filesystem path inside the pod where the blob is generated or read before it is published through a ConfigMap.
- `spec.replicas`
  Use `1` for the basic setup.

After you apply the primary manifest, wait for the generated blob ConfigMap before creating the True Cache database:

```sh
kubectl apply -f primary-sidb.yaml
kubectl get singleinstancedatabase sidb-sample
NAME          EDITION      STATUS    ROLE      VERSION       CONNECT STR             TCPS CONNECT STR   OEM EXPRESS URL
sidb-sample   Enterprise   Healthy   PRIMARY   23.26.1.0.0   10.0.2.7:1521/ORCLPRD   Not enabled        Unavailable
kubectl get configmap sidb-sample-truecache-blob
NAME                         DATA   AGE
sidb-sample-truecache-blob   1      33
```

For the primary database transport mode:

- Without TCPS:
  Leave `spec.security.tcps` unset and use the standard database listener.
- With TCPS:
  Create a Kubernetes TLS secret using your standard certificate process, then add `spec.security.tcps.enabled: true` and `spec.security.tcps.tlsSecret` to the primary SIDB manifest. If the primary is exposed outside the cluster, make sure the certificate SANs match the hostname clients or the remote True Cache cluster will use. If you want the cert-manager helper flow, refer to [`TCPS_CERT_MANAGER_SCRIPT.md`](./TCPS_CERT_MANAGER_SCRIPT.md).

### True Cache in the Same Cluster

Use when the primary SIDB is reachable inside the same cluster.

Start from this sample manifest:

- [`config/samples/sidb/singleinstancedatabase_truecache.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache.yaml)

Use these fields:

- `metadata.name`
  The True Cache SIDB resource name.
- `spec.createAs: truecache`
  Required. This switches the controller into True Cache creation mode.
- `spec.sid`
  The Oracle SID for the True Cache database. This is the cache database SID and can be different from the primary SID.
- `spec.edition: enterprise`
  Required for True Cache.
- `spec.primarySource.databaseRef`
  References the primary SIDB resource in the same namespace. For the basic flow, this should match the primary `metadata.name`, for example `sidb-sample`.
- optional `spec.primarySource.dbName`
  Usually leave this unset for the `databaseRef` flow. Set it only when the True Cache workflow must use the primary CDB `DB_NAME` instead of the identifier derived from `spec.primarySource.databaseRef`.
- `spec.trueCache.blobConfigMapRef`
  Name of the ConfigMap generated by the primary SIDB. In the basic flow this is `<primary-name>-truecache-blob`.
- `spec.trueCache.blobConfigMapKey`
  The key inside the ConfigMap that stores the generated blob. Keep `tc_config_blob.tar.gz` unless your source blob name differs.
- `spec.trueCache.blobMountPath`
  Path inside the True Cache pod where the operator mounts the blob during bootstrap.
- `spec.trueCache.trueCacheServices`
  Service mapping in the form `PRIMARY_PDB_NAME:PRIMARY_SERVICE_NAME:TRUECACHE_SERVICE_NAME`.
  The first value is the primary PDB name.
  In the example, `APPPDB1` is the primary PDB name, `tpdb_primary` is the primary database service, and `tpdb_cache` is the service exposed through True Cache.
- optional `spec.trueCache.autoTCServiceRegistration`
  Default `false`. When `false`, the primary-side service creation, startup, and True Cache association remain manual primary-host steps. When `true`, the True Cache pod invokes the checked-in primary-host helper script through `DBMS_SCHEDULER`.
- `spec.trueCache.truedbUniqueName`
  Unique database name for the True Cache database inside the Data Guard and True Cache configuration.
- `spec.security.secrets.tde`
  References the TDE wallet password secret required for the basic True Cache setup.
- `spec.image`
  Use a True Cache capable database image.
- `spec.persistence.oradata`
  Storage for the True Cache datafiles.
- `spec.replicas: 1`
  Keep True Cache at one replica for the basic setup.
- optional `spec.services.external.isKeep`
  Preserves the operator-managed external Service across SIDB delete and recreate by omitting the SIDB controller owner reference from that Service. Use this together with a fixed NLB frontend IP when you want redeployments to reuse the same OCI NLB instead of reprovisioning it.
- optional `spec.hostAliases`
  Use this only if the primary name cannot resolve through cluster DNS and you need static host-to-IP entries.

Apply the True Cache manifest only after the primary SIDB is ready and the blob ConfigMap exists:

```sh
kubectl apply -f singleinstancedatabase_truecache.yaml
singleinstancedatabase.database.oracle.com/truecache created
kubectl get singleinstancedatabase truecache
kubectl describe singleinstancedatabase truecache
```

Before applying the True Cache manifest:

- create a Kubernetes Secret for the primary database `SYS` password and reference it through `spec.security.secrets.admin`
  For example: `kubectl create secret generic db-admin-secret --from-literal=oracle_pwd='<primary-sys-password>'`
- create a Kubernetes Secret for the TDE wallet password and reference it through `spec.security.secrets.tde`
  For example: `kubectl create secret generic tde-wallet-secret --from-literal=tde_wallet_pwd='<tde-wallet-password>'`
- if the external primary service name differs from the primary CDB `DB_NAME`, set `spec.primarySource.dbName` explicitly so the True Cache DBCA flow does not have to infer it from the service name
- ensure `configure-primary-truecache-service.sh` is present on the primary host and executable
  In the supported extension-image workflow, where the primary also uses the same True Cache extension image, the helper is already present at `/home/oracle/configure-primary-truecache-service.sh`.
  Otherwise, copy `docker-images/OracleDatabase/SingleInstance/samples/truecache/configure-primary-truecache-service.sh` to the primary host and make it executable.
  This is optional for manual registration guidance and required for `spec.trueCache.autoTCServiceRegistration=true`.
  On RAC primaries, place the script at the same path on every node where the scheduler job might run.
  Keep the helper owned by `oracle:oinstall` and executable, for example mode `750` or `755`.
  On RAC primaries that use `spec.trueCache.autoTCServiceRegistration=true`, verify that the primary DB home `rdbms/admin/externaljob.ora` runs external jobs as the Oracle software owner, for example `run_user = oracle` and `run_group = oinstall`. The automatic path invokes the helper through `DBMS_SCHEDULER`; the default `nobody:nobody` setting can fail even when the script works interactively as `oracle`.
  On RAC primaries, also run a real `DBMS_SCHEDULER` executable smoke test and verify the generated `/tmp/extjob_id_test.out` file shows the Oracle DB software owner, for example `uid=... (oracle)`. If the file shows any other OS user, fix the scheduler runtime before relying on automatic registration.
  To use a non-default location, set `spec.envVars` like:

  ```yaml
  envVars:
    - name: PRIMARY_TC_SERVICE_SCRIPT_PATH
      value: /custom/path/configure-primary-truecache-service.sh
  ```

Provisioning success and primary-side service association are separate checks:

- `DATABASE IS READY TO USE` confirms the True Cache database was created successfully.
- It does not by itself prove that the primary-side service was created, started, and associated with the True Cache service.
- With `spec.trueCache.autoTCServiceRegistration=false`, that primary-side association remains a separate manual step on the primary host.
- With `spec.trueCache.autoTCServiceRegistration=true`, verify that the primary-host helper script exists at the configured path. In the supported extension-image workflow, the default path is already `/home/oracle/configure-primary-truecache-service.sh`.
- On RAC primaries with `spec.trueCache.autoTCServiceRegistration=true`, also verify the primary DB home `rdbms/admin/externaljob.ora` runs external jobs as the Oracle software owner instead of the default `nobody:nobody`.
- On RAC primaries, also verify the scheduler smoke test runs the helper as the Oracle software owner before relying on automatic registration.

Verify the primary-side association separately on the primary database:

```sql
SELECT service_id, name, true_cache_service
FROM   v$active_services
ORDER  BY service_id;
```

For the mapped primary service, `TRUE_CACHE_SERVICE` should show the expected True Cache service name after a successful association.

For the same-cluster transport mode:

- Without TCPS:
  Use the manifest exactly as shown above. Keep `spec.security.tcps` unset on the True Cache SIDB.
- With TCPS:
  Keep `spec.primarySource.databaseRef` and the blob fields unchanged, then add a TCPS secret to each SIDB that should terminate TCPS. For a cert-manager based TLS secret setup, refer to [`TCPS_CERT_MANAGER_SCRIPT.md`](./TCPS_CERT_MANAGER_SCRIPT.md).

Primary SIDB TCPS fields:

```yaml
security:
  secrets:
    admin:
      secretName: db-admin-secret
      secretKey: oracle_pwd
      keepSecret: true
    tde:
      secretName: tde-wallet-secret
      secretKey: tde_wallet_pwd
  tcps:
    enabled: true
    tlsSecret: sidb-primary-tcps-tls
```

True Cache SIDB TCPS fields:

```yaml
security:
  secrets:
    admin:
      secretName: db-admin-secret
      secretKey: oracle_pwd
      keepSecret: true
    tde:
      secretName: tde-wallet-secret
      secretKey: tde_wallet_pwd
  tcps:
    enabled: true
    tlsSecret: sidb-truecache-tcps-tls
```

For same-cluster TCPS, make sure:

- the TLS secret exists before applying the SIDB that references it
- the certificate SANs match the names clients use to reach the primary or True Cache endpoint

For this basic same-cluster flow, make sure all of the following are true:

- the primary SIDB is healthy before you create the True Cache SIDB
- `spec.primarySource.databaseRef` matches the primary SIDB name exactly
- `spec.trueCache.blobConfigMapRef` matches the generated ConfigMap name exactly
- the primary and True Cache manifests use compatible enterprise images
- the service mapping in `spec.trueCache.trueCacheServices` reflects the primary PDB and services you actually want clients to use

### True Cache with an External Primary

Use when the primary database is outside the cluster or reachable through external/private network paths.

For a cross-cluster setup, this flow usually has two resources:

- a primary SIDB in the primary cluster that generates the True Cache blob and exposes a reachable external service
- a True Cache SIDB in the remote cluster that uses `spec.primarySource.connectString` to reach that primary endpoint

Use these sample manifests:

- Primary cluster with blob generation, external service, and TCPS:
  [`config/samples/sidb/singleinstancedatabase_truecache_primary_tcps_peered.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache_primary_tcps_peered.yaml)
- True Cache cluster with an external primary and external service:
  [`config/samples/sidb/singleinstancedatabase_truecache_external.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache_external.yaml)

In this pattern:

- the primary SIDB generates `sidb-sample-truecache-blob`
- the primary `services.external` section creates the endpoint that the remote True Cache cluster uses
- the hostname or IP published by that service must match what you place in `spec.primarySource.connectString`
- if TCPS is enabled, the primary certificate SANs must match that hostname

Use these fields:

- `metadata.name`
  The True Cache SIDB resource name in the cluster where you are creating the cache database.
- `spec.edition: enterprise`
  Required for True Cache.
- `spec.createAs: truecache`
  Required. This switches the controller into True Cache creation mode.
- `spec.primarySource.connectString`
  The reachable listener endpoint for the external primary database. In a cross-cluster setup, this normally points to the primary SIDB external service hostname or IP and its listener port. The service name or SID segment in the connect string must identify the primary database, not the True Cache SID.
- optional `spec.primarySource.dbName`
  Leave this unset when `spec.primarySource.connectString` already uses the correct reachable primary service or SID. Set it only when True Cache must use the external primary CDB `DB_NAME` instead of the service or SID from `spec.primarySource.connectString`.
- `spec.sid`
  The Oracle SID for the True Cache database. This can be different from the primary SID referenced by `spec.primarySource.connectString`.
- `spec.security.secrets.admin`
  References the primary database `SYS` password secret. In the current external-primary True Cache flow, provide this secret through `spec.security.secrets.admin`.
- `spec.security.secrets.tde`
  References the TDE wallet password secret required for the external-primary True Cache setup.
- `spec.trueCache.blobConfigMapRef`
  ConfigMap containing the True Cache blob generated from the primary side. For an external primary, generate or export the blob from the primary cluster and create the ConfigMap in the True Cache cluster before applying the True Cache SIDB.
- `spec.trueCache.blobConfigMapKey`
  The key inside the ConfigMap that stores the blob. Keep `tc_config_blob.tar.gz` unless your blob key differs.
- `spec.trueCache.blobMountPath`
  Path inside the pod where the operator mounts the blob during bootstrap.
- `spec.trueCache.truedbUniqueName`
  Unique database name for the True Cache database.
- `spec.trueCache.trueCacheServices`
  Service mapping in the form `PRIMARY_PDB_NAME:PRIMARY_SERVICE_NAME:TRUECACHE_SERVICE_NAME`.
  The first value is the primary PDB name.
- optional `spec.trueCache.autoTCServiceRegistration`
  Default `false`. When `false`, the primary administrator manually creates, starts, and associates the primary-side service on the primary host. When `true`, the True Cache pod executes the primary-host helper script through `DBMS_SCHEDULER`.
- `spec.image`
  Use a True Cache capable image.
- `spec.persistence.oradata`
  Storage for the True Cache datafiles.
- optional `spec.hostAliases`
  Use this if the external primary hostname is not resolvable through cluster DNS and you need a static host-to-IP entry.
- `spec.services.external`
  For the cross-cluster pattern documented here, expose the True Cache endpoint through an external service so remote clients or peer environments can reach it consistently. Keep TCP enabled for the non-TCPS flow.

External-primary RAC example:

```yaml
apiVersion: database.oracle.com/v4
kind: SingleInstanceDatabase
metadata:
  name: tck8node1
spec:
  sid: TCK8DB1
  edition: enterprise
  createAs: truecache
  primarySource:
    connectString: "racdb26260-scan.example.com:1521/DB0515_qw6_iad.example.com"
  trueCache:
    blobConfigMapRef: sidb-sample-truecache-blob
    blobConfigMapKey: tc_config_blob.tar.gz
    blobMountPath: /stage/tc_config_blob.tar.gz
    truedbUniqueName: TCK8DB1_FRA
    trueCacheServices:
      - "DB0515_PDB1:tcokeprim.example.com:tcokenodes.example.com"
    autoTCServiceRegistration: true
  security:
    secrets:
      admin:
        secretName: db-admin-secret
        secretKey: oracle_pwd
        keepSecret: true
      tde:
        secretName: tde-wallet-secret
        secretKey: tde_wallet_pwd
```

In this RAC example:

- `spec.primarySource.connectString` uses the reachable RAC SCAN listener and the primary service that resolves to the primary database.
- `spec.primarySource.dbName` is still optional. Leave it unset unless the primary CDB `DB_NAME` differs from the service name in `spec.primarySource.connectString` and True Cache must use that `DB_NAME` explicitly.
- `spec.trueCache.trueCacheServices` uses `PRIMARY_PDB_NAME:PRIMARY_SERVICE_NAME:TRUECACHE_SERVICE_NAME`.

If you want explicit customer-style RAC variants instead of editing a generic sample, use one of these checked-in manifests:

- [singleinstancedatabase_truecache_customer_fra_rac_scheduler_credential.yaml](/scratch/sauahuja/gobin/goprojects/src/github.com/user/dboper/sidb/oracle-database-operator/config/samples/sidb/singleinstancedatabase_truecache_customer_fra_rac_scheduler_credential.yaml)
  Legacy filename. Do not use this sample until the scheduler-credential path is fully validated.

For the external-primary transport mode:

- Without TCPS:
  Keep `spec.primarySource.connectString` on the standard listener port, typically `1521`, and leave `spec.security.tcps` unset. In this mode, both the primary and the True Cache external services expose TCP.
- With TCPS:
  Use a reachable TCPS connect string, provide the required TLS secret, and enable TCPS on the True Cache SIDB. In this mode, both the primary and the True Cache external services expose TCPS on the corresponding port. If you want the cert-manager helper flow for these TLS secrets, refer to [`TCPS_CERT_MANAGER_SCRIPT.md`](./TCPS_CERT_MANAGER_SCRIPT.md).

External-primary TCPS additions:

```yaml
primarySource:
  connectString: "sidb-sample.internal.example.com:2484/ORCLPRD"
# The /ORCLPRD segment identifies the primary database service or SID.
# The True Cache SID can be different, for example ORCLTC.
security:
  secrets:
    tde:
      secretName: tde-wallet-secret
      secretKey: tde_wallet_pwd
  tcps:
    enabled: true
    tlsSecret: sidb-truecache-tcps-tls
```

For the TCPS variant, update the True Cache external service to expose TCPS as well:

```yaml
services:
  external:
    type: LoadBalancer
    externalTrafficPolicy: Local
    annotations:
      external-dns.alpha.kubernetes.io/hostname: "truecache.internal.example.com"
    tcp:
      enabled: true
      port: 1521
    tcps:
      enabled: true
      port: 2484
```

Use a direct IP in `spec.primarySource.connectString` only when that is the actual stable, reachable endpoint for the external primary or when you are temporarily working around stale or missing DNS. Prefer a hostname when DNS resolution is correct and stable.

For external-primary TCPS, make sure:

- the external primary hostname in `spec.primarySource.connectString` resolves inside the True Cache pod
- the external primary really accepts TCPS on the configured port
- the primary cluster service endpoint exposed through `spec.services.external` is the same endpoint family the remote cluster uses
- the TLS secret exists before the True Cache SIDB references it
- the certificate SANs match the hostnames used for the external primary and for any exposed True Cache service

Before applying this manifest, make sure all of the following are ready:

- the primary SIDB is healthy and its external service is already created if the remote cluster connects through that service
- the external primary is reachable from the True Cache cluster on the required port
- the hostname used in `spec.primarySource.connectString` resolves inside the True Cache pod, or an equivalent `spec.hostAliases` entry is provided
- the blob ConfigMap referenced by `spec.trueCache.blobConfigMapRef` already exists in the target namespace
- any required TLS or TCPS secret already exists before you enable `spec.security.tcps`
- if you expose the True Cache endpoint through `spec.services.external`, the chosen hostname resolves to the resulting service address for your clients

For cross-cluster external-primary setups, also make sure:

- the generated blob ConfigMap is exported or recreated in the namespace and cluster where the True Cache SIDB will run
- the True Cache pod can connect to the primary database endpoint on the required listener port, typically TCP `1521` or TCP `2484` when TCPS is enabled
- the names used by the manifests resolve from the opposite cluster, or equivalent entries are provided through `spec.hostAliases`
- any hostnames published for `sidb-sample.internal.example.com` or `truecache.internal.example.com` resolve to the corresponding reachable service IPs or load balancer addresses
- any TCPS secret you supply has certificate SANs that match the hostnames clients and peer clusters use to reach those endpoints

Apply and verify:

```sh
kubectl get configmap sidb-sample-truecache-blob
kubectl apply -f truecache-external-primary.yaml
kubectl get singleinstancedatabase truecache
kubectl describe singleinstancedatabase truecache
```

For external-primary provisioning, also verify the primary-side service association separately from the True Cache pod readiness:

- `DATABASE IS READY TO USE` means the True Cache database setup completed.
- It does not guarantee that the primary-side service mapping was associated successfully.
- Wallet-backed True Cache authentication covers DBCA creation only. The primary-side service association still requires a separate manual step on the primary host after the True Cache database is provisioned.

Check the primary database after provisioning:

```sql
SELECT service_id, name, true_cache_service
FROM   v$active_services
ORDER  BY service_id;
```

For the mapped primary service, `TRUE_CACHE_SERVICE` should show the expected True Cache service name.

## Networking, Security, and Runtime Options

### External Service Exposure

Use `spec.services.external` to expose TCP or TCPS access.

Supported `spec.services.external.type` values are `ClusterIP`, `NodePort`, `LoadBalancer`, and `Disabled`. Use `ClusterIP` when you want an explicit tester-facing in-cluster Service without exposing the database outside the cluster.

Key fields:

- `spec.services.external.type`
- `spec.services.external.tcp.enabled`
- `spec.services.external.tcps.enabled`
- `spec.services.external.annotations`
- `spec.services.external.externalTrafficPolicy`

References:

- [`config/samples/sidb/singleinstancedatabase.yaml`](../../config/samples/sidb/singleinstancedatabase.yaml)

### Specifying Custom Ports

Use custom external listener ports when your environment requires non-default service ports.

Examples:

- `spec.services.external.tcp.port`
- `spec.services.external.tcps.port`

This is useful for:

- ClusterIP services with explicit in-cluster listener ports
- LoadBalancer services with explicit frontend listener ports
- TCPS exposure on a dedicated external port
- standardizing service ports across environments

### Enabling TCPS Connections

Use `spec.security.tcps` together with `spec.services.external.tcps`.

Create and manage the Kubernetes TLS secret using your standard certificate process, then reference that secret from `spec.security.tcps.tlsSecret`.

Primary sample:

- [`config/samples/sidb/singleinstancedatabase_tcps.yaml`](../../config/samples/sidb/singleinstancedatabase_tcps.yaml)

Key fields:

- `spec.security.tcps.enabled`
- `spec.security.tcps.tlsSecret`
- `spec.security.tcps.certRenewInterval`
- `spec.services.external.tcps`

### Host Aliases

Use `spec.hostAliases` when specific names must resolve to fixed IPs without relying on cluster DNS.

This is especially useful for:

- external primary database names
- private DNS gaps in True Cache or advanced networking setups

### Database Pod Resources

Use `spec.resources` to set Kubernetes requests and limits.

For enterprise databases, size CPU and memory intentionally for your workload and storage characteristics.

Use `spec.shmSize` to configure a memory-backed `/dev/shm` volume mounted into the database pod. If omitted, the pod uses the container runtime default. For production databases, size `shmSize` at least to the configured SGA or `SGA_MAX_SIZE`, with additional headroom, and keep the pod memory limit large enough for SGA, PGA, database processes, and operating system overhead.

Example:

```yaml
spec:
  initParams:
    sgaTarget: 6144
    pgaAggregateTarget: 2048
  shmSize: 8Gi
  resources:
    limits:
      memory: 16Gi
```

### Multiple Replicas

Use `spec.replicas > 1` when you want faster failover or lower downtime during patching.

Important:

- only one pod mounts and opens the database at a time
- additional replicas wait to take over if the active pod fails
- with `ReadWriteOnce`, replicas normally schedule on the same attached-storage node

## Storage, Lifecycle, and Maintenance

### Dynamic Persistence

Use `spec.persistence.oradata` with a storage class for dynamic provisioning.

Key fields:

- `spec.persistence.oradata.size`
- `spec.persistence.oradata.storageClass`
- `spec.persistence.oradata.accessMode`

### Storage Expansion

If the storage class supports expansion, patch the storage size upward. Shrinking is not supported.

### Static Persistence

Use these fields when binding to a pre-existing volume:

- `spec.persistence.datafilesVolumeName`
- empty or storage-class-specific provisioning choices appropriate for your environment

### Write Permissions and Scripts Volume

Use:

- `spec.persistence.setWritePermissions`
- `spec.persistence.scriptsVolumeName`

The scripts volume can provide `setup` and `startup` scripts for custom execution.

### Switching Database Modes

For standby workflows, use:

- `spec.createAs`
- `spec.convertToSnapshotStandby` is the legacy SIDB-only conversion field. For Data Guard Broker topology resources, use `spec.operations.roleConversion` described above.

### Changing Init Parameters

Use `spec.initParams` for supported initialization settings such as:

- `cpuCount`
- `processes`
- `sgaTarget`
- `pgaAggregateTarget`

### Immutable or Sensitive Areas

Treat these as carefully managed fields:

- storage layout and bound volumes
- source database references for clone/standby/truecache
- image family and edition combinations
- TCPS and TDE configuration that affects bootstrap paths

### Execute Custom Scripts

Mount a scripts volume and organize scripts under the controller-supported `setup` and `startup` directories.

If you use custom scripts, ensure the optional persistent-volume RBAC has been applied.

### Maintenance Operations

If manual maintenance is required:

1. Enter the pod:

   ```sh
   kubectl exec -it <pod-name> -- /bin/bash
   ```

2. Inspect environment and Oracle paths:

   ```sh
   env
   ```

3. Connect as SYSDBA if needed:

   ```sh
   sqlplus / as sysdba
   ```

## ORDS and APEX

Oracle REST Data Services (ORDS) is commonly deployed after a SIDB is ready. It provides HTTP access to database services such as Database API, REST-enabled schemas, Database Actions, and the MongoDB API. The ORDS controller also verifies APEX availability and publishes the APEX URL in status when APEX is available through the ORDS deployment.

### Provision ORDS

Samples:

- [`config/samples/sidb/oraclerestdataservice.yaml`](../../config/samples/sidb/oraclerestdataservice.yaml)
- [`config/samples/sidb/oraclerestdataservice_create.yaml`](../../config/samples/sidb/oraclerestdataservice_create.yaml)
- [`config/samples/sidb/oraclerestdataservice_secrets.yaml`](../../config/samples/sidb/oraclerestdataservice_secrets.yaml)

Recommended flow:

1. Create the SIDB.
2. Wait until the SIDB reports `Ready`.
3. Create the database admin password Secret and the ORDS public user password Secret.
4. Apply the `OracleRestDataService` custom resource.
5. Verify ORDS, Database Actions, MongoDB API, and APEX URLs from ORDS status.

The current samples use explicit password mappings so the controller always knows which Secret key to read and whether the Secret should be retained:

```yaml
apiVersion: database.oracle.com/v4
kind: OracleRestDataService
metadata:
  name: ords-sample
  namespace: default
spec:
  databaseRef: sidb-sample

  adminPassword:
    secretName: db-admin-secret
    secretKey: oracle_pwd
    keepSecret: true

  ordsPassword:
    secretName: ords-secret
    secretKey: oracle_pwd
    keepSecret: true

  image:
    pullFrom: container-registry.oracle.com/database/ords-developer:latest

  mongoDbApi: true
  replicas: 1

  restEnableSchemas:
  - schemaName: schema1
    enable: true
    urlMapping:
  - schemaName: schema2
    enable: true
    urlMapping: myschema
```

Create the ORDS public user password Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ords-secret
  namespace: default
type: Opaque
stringData:
  oracle_pwd: <ords-public-user-password>
```

The `adminPassword.secretName` should point to the SIDB database admin password Secret, for example `db-admin-secret`. That Secret must contain the key named by `adminPassword.secretKey`, normally `oracle_pwd`.

### ORDS Secret Fields

`adminPassword` identifies the database admin password used by the ORDS controller when it connects to the referenced SIDB. The controller uses this password to validate database access, create common ORDS setup users, create the ORDS connection string during pod initialization, verify APEX, and clean up ORDS during deletion.

`ordsPassword` identifies the password used for ORDS-enabled schemas and `ORDS_PUBLIC_USER`-related work. The controller reads this Secret when it creates or updates REST-enabled schemas from `spec.restEnableSchemas`.

Each password reference has the same fields:

- `secretName`
  Name of the Kubernetes Secret in the same namespace as the `OracleRestDataService` resource.
- `secretKey`
  Key inside the Secret data. Use `oracle_pwd` unless the Secret intentionally uses another key.
- `keepSecret`
  When `true`, the operator leaves the Secret in place after successful ORDS setup. This is the safest sample value because the same Secret may be needed again for reconcile, APEX verification, schema changes, or uninstall. When `false`, the operator may delete the Secret after it is no longer needed.

The controller validates that the Secret reference exists, that the requested key is present, and that the password is not empty before using it. Missing names, missing keys, and empty values are reported through warning events on the ORDS resource.

### Structured Secret Form

For newer v4 manifests, the same password references can be grouped under `spec.security.secrets`. This is the preferred long-term structure because security-related values are kept together:

```yaml
spec:
  databaseRef: sidb-sample
  security:
    secrets:
      databaseAdmin:
        secretName: db-admin-secret
        secretKey: oracle_pwd
        keepSecret: true
      ordsPublicUser:
        secretName: ords-secret
        secretKey: oracle_pwd
        keepSecret: true
  replicas: 1
```

If both forms are present, the grouped `spec.security.secrets` values take precedence. The legacy-compatible `spec.adminPassword` and `spec.ordsPassword` fields continue to work, but admission warnings guide users toward the grouped form.

### ORDS Resource Fields

Common fields:

- `databaseRef`
  Name of the `SingleInstanceDatabase` that ORDS connects to. The ORDS controller waits for this SIDB to be ready before completing database setup.
- `image.pullFrom`
  ORDS container image. The sample uses `container-registry.oracle.com/database/ords-developer:latest`.
- `image.pullSecrets`
  Optional image pull Secret for private registries.
- `replicas`
  Number of ORDS pods. The sample sets `1` explicitly.
- `loadBalancer`
  When `true`, creates a LoadBalancer service. When `false`, creates a NodePort service.
- `serviceAnnotations`
  Optional cloud-provider annotations for the ORDS Service, for example internal load balancer annotations.
- `mongoDbApi`
  Enables the ORDS MongoDB API listener and publishes `status.mongoDbApiAccessUrl` when available.
- `oracleService`
  Optional database service name override. If omitted, the controller uses the referenced SIDB service details.
- `serviceAccountName`
  Kubernetes ServiceAccount for ORDS pods. Use the OpenShift service account if deploying on OpenShift.
- `persistence`
  Optional dedicated persistent storage for ORDS configuration. If omitted, ORDS uses persistent storage from the referenced SIDB.
- `nodeSelector`
  Optional node placement labels for ORDS pods and related PVC selection.

### Verify ORDS

```sh
kubectl get oraclerestdataservice
kubectl describe oraclerestdataservice ords-sample
```

Useful status fields include:

- `status.databaseApiUrl`
  Base URL for ORDS Database API requests.
- `status.databaseActionsUrl`
  URL for Database Actions.
- `status.mongoDbApiAccessUrl`
  MongoDB API connection URL when `spec.mongoDbApi` is enabled.
- `status.apexUrl`
  APEX URL after APEX verification completes.

### Database API, MongoDB API, and Advanced ORDS Usage

Use ORDS when you need:

- Database API access
- MongoDB API access
- REST-enabled SQL
- Oracle Data Pump APIs
- Database Actions

### APEX Installation

APEX is handled as part of the ORDS workflow. After the ORDS pod is ready, the controller connects to the referenced SIDB using `adminPassword`, checks the APEX installation state, sets `status.apexConfigured`, updates the SIDB `status.apexInstalled` flag, and publishes `status.apexUrl` when the ORDS Service endpoint is known.

If `status.apexUrl` is still empty, check:

- the ORDS pod is ready
- the referenced SIDB is `Ready`
- `adminPassword.secretName` and `adminPassword.secretKey` point to a valid admin password Secret
- the ORDS Service has an address or NodePort
- warning events on the ORDS resource for Secret or APEX verification failures

### Delete ORDS

Delete ORDS before deleting the referenced SIDB:

```sh
kubectl delete oraclerestdataservice ords-sample
```

## Sample Catalog

Use this table as a quick map from user goal to sample file.

| Use case | Sample |
| --- | --- |
| Full template | [`config/samples/sidb/singleinstancedatabase.yaml`](../../config/samples/sidb/singleinstancedatabase.yaml) |
| New primary database | [`config/samples/sidb/singleinstancedatabase_create.yaml`](../../config/samples/sidb/singleinstancedatabase_create.yaml) |
| Prebuilt database | [`config/samples/sidb/singleinstancedatabase_prebuiltdb.yaml`](../../config/samples/sidb/singleinstancedatabase_prebuiltdb.yaml) |
| Express edition | [`config/samples/sidb/singleinstancedatabase_express.yaml`](../../config/samples/sidb/singleinstancedatabase_express.yaml) |
| Free edition | [`config/samples/sidb/singleinstancedatabase_free.yaml`](../../config/samples/sidb/singleinstancedatabase_free.yaml) |
| Free Lite edition | [`config/samples/sidb/singleinstancedatabase_free-lite.yaml`](../../config/samples/sidb/singleinstancedatabase_free-lite.yaml) |
| Clone database | [`config/samples/sidb/singleinstancedatabase_clone.yaml`](../../config/samples/sidb/singleinstancedatabase_clone.yaml) |
| Standby database | [`config/samples/sidb/singleinstancedatabase_standby.yaml`](../../config/samples/sidb/singleinstancedatabase_standby.yaml) |
| Patch database | [`config/samples/sidb/singleinstancedatabase_patch.yaml`](../../config/samples/sidb/singleinstancedatabase_patch.yaml) |
| TCPS-enabled SIDB | [`config/samples/sidb/singleinstancedatabase_tcps.yaml`](../../config/samples/sidb/singleinstancedatabase_tcps.yaml) |
| Data Guard Broker | [`config/samples/sidb/dataguardbroker.yaml`](../../config/samples/sidb/dataguardbroker.yaml) |
| True Cache in-cluster | [`config/samples/sidb/singleinstancedatabase_truecache.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache.yaml) |
| True Cache external primary | [`config/samples/sidb/singleinstancedatabase_truecache_external.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache_external.yaml) |
| True Cache cross-cluster TCPS primary | [`config/samples/sidb/singleinstancedatabase_truecache_primary_tcps_peered.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache_primary_tcps_peered.yaml) |
| True Cache same-cluster TCPS primary | [`config/samples/sidb/singleinstancedatabase_truecache_same_cluster_tcps.yaml`](../../config/samples/sidb/singleinstancedatabase_truecache_same_cluster_tcps.yaml) |
| ORDS base sample | [`config/samples/sidb/oraclerestdataservice.yaml`](../../config/samples/sidb/oraclerestdataservice.yaml) |
| ORDS create example | [`config/samples/sidb/oraclerestdataservice_create.yaml`](../../config/samples/sidb/oraclerestdataservice_create.yaml) |
| ORDS secrets | [`config/samples/sidb/oraclerestdataservice_secrets.yaml`](../../config/samples/sidb/oraclerestdataservice_secrets.yaml) |
| SIDB secrets | [`config/samples/sidb/singleinstancedatabase_secrets.yaml`](../../config/samples/sidb/singleinstancedatabase_secrets.yaml) |
| OpenShift RBAC | [`config/samples/sidb/openshift_rbac.yaml`](../../config/samples/sidb/openshift_rbac.yaml) |

### Same-cluster True Cache with TCPS

This validated sample keeps SIDB and True Cache in the same cluster, exposes the primary on `2484`, and uses `primarySource.databaseRef` instead of a raw connect string. It is the preferred pattern when the primary is already reachable through the Kubernetes service name and the operator manages the TCPS secret.

Primary SIDB:

```yaml
apiVersion: database.oracle.com/v4
kind: SingleInstanceDatabase
metadata:
  name: sidb-sample
  namespace: default
spec:
  sid: ORCLPRD
  pdbName: APPPDB1
  createAs: primary
  edition: enterprise
  security:
    secrets:
      admin:
        secretName: db-admin-secret
        secretKey: oracle_pwd
        keepSecret: true
      tde:
        secretName: tde-wallet-secret
        secretKey: tde_wallet_pwd
    tcps:
      enabled: true
      tlsSecret: sidb-primary-tcps-tls
  image:
    pullFrom: phx.ocir.io/<tenancy>/db-repo/oracle/database:truecache-23.26.0-ee
    prebuiltDB: false
    imagePullPolicy: Always
  trueCache:
    generateEnabled: true
    generatePath: /tmp/tc_config_blob.tar.gz
  services:
    external:
      type: LoadBalancer
      externalTrafficPolicy: Local
      annotations:
        oci.oraclecloud.com/load-balancer-type: nlb
        oci-network-load-balancer.oraclecloud.com/internal: "true"
        oci-network-load-balancer.oraclecloud.com/subnet: ocid1.subnet.oc1.<region>.<placeholder-subnet-ocid>
        external-dns.alpha.kubernetes.io/hostname: sidb-sample.internal.example.com
      tcp:
        enabled: true
        port: 1521
      tcps:
        enabled: true
        port: 2484
  replicas: 1
```

True Cache:

```yaml
apiVersion: database.oracle.com/v4
kind: SingleInstanceDatabase
metadata:
  name: truecache
  namespace: default
spec:
  sid: ORCLTC
  createAs: truecache
  edition: enterprise
  primarySource:
    databaseRef: sidb-sample
  trueCache:
    blobConfigMapRef: sidb-sample-truecache-blob
    blobConfigMapKey: tc_config_blob.tar.gz
    blobMountPath: /stage/tc_config_blob.tar.gz
    truedbUniqueName: truecache_tc
    trueCacheServices:
      - "APPPDB1:TPDB_PRIMARY:tpdb_cache"
    autoTCServiceRegistration: true
  security:
    secrets:
      admin:
        secretName: db-admin-secret
        secretKey: oracle_pwd
        keepSecret: true
      tde:
        secretName: tde-wallet-secret
        secretKey: tde_wallet_pwd
    tcps:
      enabled: true
      tlsSecret: sidb-primary-tcps-tls
  image:
    pullFrom: phx.ocir.io/<tenancy>/db-repo/oracle/database:truecache-23.26.0-ee
    prebuiltDB: false
    imagePullPolicy: Always
  services:
    external:
      type: LoadBalancer
      externalTrafficPolicy: Local
      annotations:
        oci.oraclecloud.com/load-balancer-type: nlb
        oci-network-load-balancer.oraclecloud.com/internal: "true"
        oci-network-load-balancer.oraclecloud.com/subnet: ocid1.subnet.oc1.<region>.<placeholder-subnet-ocid>
        external-dns.alpha.kubernetes.io/hostname: truecache.internal.example.com
      tcp:
        enabled: true
        port: 1521
      tcps:
        enabled: true
        port: 2484
  replicas: 1
```

Validated connection checks:

```bash
sqlplus sys/<database-password>@"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=sidb-sample.internal.example.com)(PORT=2484))(CONNECT_DATA=(SERVICE_NAME=ORCLPRD)))" as sysdba
sqlplus sys/<database-password>@"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=sidb-sample.internal.example.com)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=ORCLPRD)))" as sysdba
```

## Additional Information

Detailed hands-on setup instructions are also available in LiveLab format:

- <https://oracle.github.io/cloudtestdrive/AppDev/database-operator/workshops/freetier/?lab=introduction>
