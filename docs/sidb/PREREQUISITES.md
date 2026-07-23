## Deployment Prerequisites
To deploy Oracle Single Instance Database in Kubernetes using the OraOperator, complete these steps. 

Unless noted otherwise, the examples below use the `default` namespace. Create the required secrets in the same namespace where you plan to create the SIDB resources.

* ### Prepare Oracle Container Images

  You can either build Single Instance Database Container Images from the source, following the instructions at [https://github.com/oracle/docker-images/tree/main/OracleDatabase/SingleInstance](https://github.com/oracle/docker-images/tree/main/OracleDatabase/SingleInstance), or you can use the the pre-built images available at [https://container-registry.oracle.com](https://container-registry.oracle.com) by signing in and accepting the required license agreement.

  Oracle Database Releases Supported: Enterprise and Standard Edition for Oracle Database 19c, and later releases. Express Edition for Oracle Database 21.3.0 only. Oracle Database Free 23.2.0 and later Free releases
  
  Build Oracle REST Data Service Container Images from source following the instructions at [https://github.com/oracle/docker-images/tree/main/OracleRestDataServices](https://github.com/oracle/docker-images/tree/main/OracleRestDataServices).     
  The supported Oracle REST Data Service version is 21.4.2

* ### Ensure Sufficient Disk Space in Kubernetes Worker Nodes 

  Provision Kubernetes worker nodes. Oracle recommends you provision them with 250 GB or more free disk space, which is required for pulling the base and patched database container images. If you are doing a Cloud deployment, then you can choose to increase the custom boot volume size of the worker nodes. 

* ### Set Up Kubernetes and Volumes for Database Persistence

  Set up an on-premises Kubernetes cluster, or subscribe to a managed Kubernetes service, such as Oracle Cloud Infrastructure Container Engine for Kubernetes. Use a dynamic volume provisioner or pre-provision static persistent volumes manually. These volumes are required for persistent storage of the database files.

  For more more information about creating persistent volumes, see: [https://kubernetes.io/docs/concepts/storage/persistent-volumes/](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

* ### Create Required Kubernetes Secrets

  Before you apply SIDB manifests, create the secrets referenced by the sample you plan to use.

  **Image pull secret**

  Create this when your database image is hosted in a private registry such as Oracle Container Registry and your SIDB manifest sets `spec.image.pullSecrets`, for example `oracle-container-registry-secret`.

  ```
  kubectl create secret docker-registry oracle-container-registry-secret \
    --docker-server=container-registry.oracle.com \
    --docker-username='<registry-username>' \
    --docker-password='<registry-password>' \
    --docker-email='<email-address>'
  ```

  **Database admin password secret**

  Create the admin password secret referenced by `spec.security.secrets.admin`, for example `db-admin-secret`.

  ```
  kubectl create secret generic db-admin-secret \
    --from-literal=oracle_pwd='<database-password>'
  ```

  You can also start from the shipped sample:

  - [`../../config/samples/sidb/singleinstancedatabase_secrets.yaml`](../../config/samples/sidb/singleinstancedatabase_secrets.yaml)

  That sample also includes the alternate secret names used by the prebuilt, Express, and Free SIDB samples.

* ### Create Scenario-Specific Secrets When the Sample Requires Them

  Some workflows reference additional secrets. Create them before applying the manifest that uses them.

  **TDE wallet password secret**

  Create this when your chosen SIDB or True Cache manifest includes `spec.security.secrets.tde`, for example `tde-wallet-secret` with key `tde_wallet_pwd`.

  ```
  kubectl create secret generic tde-wallet-secret \
    --from-literal=tde_wallet_pwd='<tde-wallet-password>'
  ```

  This is separate from TCPS. TDE and TCPS are different setup concerns.

  **RAC primary auto-registration prerequisite**

  If your True Cache manifest enables `spec.trueCache.autoTCServiceRegistration=true` against a RAC primary, ensure `configure-primary-truecache-service.sh` is present at the same path on every RAC node where the scheduler job might run, keep it owned by the Oracle software owner and executable, and verify the primary DB home `rdbms/admin/externaljob.ora` runs external jobs as that Oracle software owner. In the supported extension-image workflow, the default path is already `/home/oracle/configure-primary-truecache-service.sh`. Otherwise, copy the checked-in sample script there before enabling automatic registration. For example:

  ```
  run_user = oracle
  run_group = oinstall
  ```

  The automatic path launches the helper through `DBMS_SCHEDULER`. A default `run_user = nobody` / `run_group = nobody` configuration can fail even when the helper script works in an interactive `oracle` shell.

  Do not stop at `externaljob.ora`. Before enabling `spec.trueCache.autoTCServiceRegistration=true`, run a real scheduler smoke test and verify the job actually runs as `oracle`:

  ```sql
  BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
      job_name            => 'EXTJOB_ID_TEST',
      job_type            => 'EXECUTABLE',
      job_action          => '/bin/bash',
      number_of_arguments => 2,
      enabled             => FALSE,
      auto_drop           => FALSE
    );
    DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('EXTJOB_ID_TEST', 1, '-lc');
    DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE(
      'EXTJOB_ID_TEST', 2,
      'id > /tmp/extjob_id_test.out; echo ORACLE_HOME=$ORACLE_HOME >> /tmp/extjob_id_test.out; echo ORACLE_SID=$ORACLE_SID >> /tmp/extjob_id_test.out'
    );
    DBMS_SCHEDULER.RUN_JOB('EXTJOB_ID_TEST', use_current_session => TRUE);
  END;
  /
  ```

  Then verify on the RAC node where it ran:

  ```bash
  cat /tmp/extjob_id_test.out
  ```

  Expected output includes the Oracle DB software owner, for example `uid=... (oracle)`. If the file shows any other OS user, fix the scheduler runtime before relying on automatic registration.

  **TLS secret for TCPS**

  Create this when you enable `spec.security.tcps` and set `spec.security.tcps.tlsSecret`, for example `sidb-primary-tcps-tls` or `sidb-truecache-tcps-tls`.

  ```
  kubectl create secret tls sidb-primary-tcps-tls \
    --cert=/path/to/tls.crt \
    --key=/path/to/tls.key
  ```

  Create the TLS secret before applying the SIDB manifest that references it. If clients or peer clusters connect by hostname, ensure the certificate SANs match those hostnames.

  **ORDS password secret**

  Create this when you deploy Oracle REST Data Services and the ORDS manifest references `ords-secret`.

  ```
  kubectl create secret generic ords-secret \
    --from-literal=oracle_pwd='<ords-password>'
  ```

  You can also start from the shipped ORDS secret sample:

  - [`../../config/samples/sidb/oraclerestdataservice_secrets.yaml`](../../config/samples/sidb/oraclerestdataservice_secrets.yaml)

* ### Validate Secret Names Before Applying a Manifest

  Before applying a SIDB or ORDS manifest, confirm that the secret names and keys in the YAML match the secrets you created. In particular, check:

  - `spec.security.secrets.admin.secretName`
  - `spec.security.secrets.admin.secretKey`
  - `spec.security.secrets.tde.secretName`
  - `spec.security.secrets.tde.secretKey`
  - `spec.security.tcps.tlsSecret`
  - `spec.image.pullSecrets`

* ### Minikube Cluster Environment
  
  By default, when you create a cluster using the `minicube start` command, Minikube creates a node with 2GB RAM, 2 CPUs, and 20GB disk space. However, these resources (particularly disk space and RAM) may not be sufficient for running and managing Oracle Database using the OraOperator. For better performance, Oracle recommends that you configure the cluster to have a larger RAM and disk space than the Minikube default. For example, the following command creates a Minikube cluster with 8GB RAM and 100GB disk space for the Minikube VM:
  
  ```
  minikube start --memory=8g --disk-size=100g
  ```
