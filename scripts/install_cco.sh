#!/bin/bash
execCMD(){
  echo $1
  eval $1
}


gcp_project="betsol-spaces-playground"
cluster_name="testcluster"
zone="us-central1"

while [ "$1" != "" ]; do
  case $1 in
    -p | --project ) shift
                  gcp_project=$1
                  ;;
    -c | --cluster) shift
                  cluster_name=$1
                  ;;
    -z | --zone) shift
                 zone=$1
                 ;;
    -h | --help) need_help=true
                 break
                 ;;
  esac
  shift
done

# Print options information
if [ "$need_help" = true ]; then
  echo "Options:"
  echo ""
  echo "-h, --help      output usage information"
  echo "-p, --project   The project name in gcp, default value is onesnastaging"
  echo "-c, --cluster   The cluster name of kubernetes, default value is artillery-vu"
  echo "-z, --zone      THe zone of the the cluster"
  exit
fi

# Get credential of the cluster
echo "===================   Connect to the CCO cluster now ======================="
execCMD "gcloud container clusters get-credentials $CC_CLUSTER_NAME --zone=$CC_CLUSTER_ZONE --project=$gcp_project"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Connect to the cluster $CC_CLUSTER_NAME successfully!"
else
  echo "Create to the cluster $CC_CLUSTER_NAME failed!"
  exit 1
fi


# Add Config Connector to the cluster
echo "================= Add Config Connector to the CCO cluster ==================="
execCMD "gsutil cp gs://configconnector-operator/latest/release-bundle.tar.gz release-bundle.tar.gz && tar zxvf release-bundle.tar.gz && kubectl apply -f operator-system/configconnector-operator.yaml"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Config Connector to the cluster $CC_CLUSTER_NAME successfully!"
else
  echo "Config Connector to the cluster $CC_CLUSTER_NAME failed!"
  exit 1
fi

# Enable Workload Identity
# echo "================= Enable workload identity ============================="
# execCMD "gcloud container clusters update $CC_CLUSTER_NAME --workload-pool=$gcp_project.svc.id.goog  --zone=$CC_CLUSTER_ZONE --project=$gcp_project" 
# status=$?
# if [[ $status -eq 0 ]]; then
#   echo "Enable workload identity on the cluster $CC_CLUSTER_NAME successfully!"
# else
#   echo "Enable workload identity on the cluster $CC_CLUSTER_NAME failed!"
#   exit 1
# fi

# Enable Kubernetes Engine Monitoring
# echo "================= Enable Kubernetes Engine Monitoring ============================="
# execCMD "gcloud container clusters update $CC_CLUSTER_NAME --zone=$CC_CLUSTER_ZONE --project=$gcp_project --logging-service logging.googleapis.com --monitoring-service monitoring.googleapis.com" 
# status=$?
# if [[ $status -eq 0 ]]; then
#   echo "Enable Kubernetes Engine Monitoring on the cluster $CC_CLUSTER_NAME successfully!"
# else
#   echo "Enable Kubernetes Engine Monitoring on the cluster $CC_CLUSTER_NAME failed!"
#   exit 1
# fi


# Bind GCP Service Account and Kubernetes Service Account
# echo "============= Bind GCP Service Account and Kubernetes Service Account ========"
# execCMD "gcloud iam service-accounts add-iam-policy-binding ${CONFIG_CONNECTOR_SERVICE_ACCOUNT} --member=\"serviceAccount:$gcp_project.svc.id.goog[cnrm-system/cnrm-controller-manager]\" --role=\"roles/iam.workloadIdentityUser\" --project=$gcp_project"
# status=$?
# if [[ $status -eq 0 ]]; then
#   echo "Bind GCP Service Account and Kubernetes Service Account successfully!"
# else
#   echo "Bind GCP Service Account and Kubernetes Service Account failed!"
#   exit 1
# fi


# Config the kubernetes with Config Connector

echo "============= Set ConfigConnector in the CCO cluster ========"
cat > configconnector.yaml <<_EOF_
apiVersion: core.cnrm.cloud.google.com/v1beta1
kind: ConfigConnector
metadata:
  # the name is restricted to ensure that there is only one
  # ConfigConnector resource installed in your cluster
  name: configconnector.core.cnrm.cloud.google.com
spec:
 mode: cluster
 googleServiceAccount: "${CONFIG_CONNECTOR_SERVICE_ACCOUNT}"
_EOF_

echo "The Config Connector yaml is:"
cat configconnector.yaml

statusResult=0
for i in {1..6}
do
    cat configconnector.yaml | kubectl apply -f -
    status=$?
    if [[ $status -eq 0 ]]; then
        echo "Set ConfigConnector in the cluster $CC_CLUSTER_NAME successfully!"
        statusResult=1
        break
    else
        echo "Set ConfigConnector in the cluster $CC_CLUSTER_NAME failed!, after 60 seconds try again"
    fi
    sleep 60
done
if [[ $statusResult -eq 0 ]]; then
  exit 1
fi

# Create Config Connector Resource storage
echo "============= Create Config Connector Resource storage ========"
kubectl create namespace config-connector --dry-run=client -o yaml | kubectl apply -f -
annotation_result=$(kubectl get namespace config-connector -o=jsonpath='{.metadata.annotations.cnrm\.cloud\.google\.com/project-id}')
echo "The Config Connector annotation is ${annotation_result} "
if [[ $annotation_result == *"$gcp_project"* ]]; then
    echo "Config Connector Resource storage already existed in the  $CC_CLUSTER_NAME"
else
    execCMD "kubectl annotate namespace config-connector cnrm.cloud.google.com/project-id=$gcp_project"
    status=$?
    if [[ $status -eq 0 ]]; then
        echo "Create Config Connector Resource storage in the cluster $CC_CLUSTER_NAME successfully!"
    else
        echo "Create Config Connector Resource storage in the cluster $CC_CLUSTER_NAME failed!"
        exit 1
    fi
fi

# Verify the Config Connector Resouce installed
echo "============= Verify Config Connector Resource storage ========"
statusResult=0
for i in {1..10}
do
    result=$(kubectl wait -n cnrm-system --for=condition=Ready pod cnrm-controller-manager-0 | grep "pod/cnrm-controller-manager-0 condition met")

    if [[ -n "$result" ]]; then
        echo "Verify Config Connector Resource storage in the cluster $CC_CLUSTER_NAME successfully!"
        statusResult=1
        break
    else
        echo "Verify Config Connector Resource storage in the cluster $CC_CLUSTER_NAME failed!, after 60 seconds try again"
    fi
    sleep 60
done
if [[ $statusResult -eq 0 ]]; then
  exit 1
fi
