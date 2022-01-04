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
echo "===================   Connect to the cluster now ======================="
execCMD "gcloud container clusters get-credentials $CC_CLUSTER_NAME --zone=$CC_CLUSTER_ZONE --project=$gcp_project"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Connect to the cluster $CC_CLUSTER_NAME successfully!"
else
  echo "Create to the cluster $CC_CLUSTER_NAME failed!"
  exit 1
fi

# Install ssl certificate 

echo "============= Install ssl certificate  ========"
cat > certificate.yaml <<_EOF_
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: "${cluster_name}-managed-cert"
spec:
  domains: [${FRONT_DOMAINS}, ${API_DOMAINS}, ${SOCKET_DOMAINS}, ${TASK_DOMAINS}]
_EOF_
echo "The ManagedCertificate yaml is:"
cat certificate.yaml
cat certificate.yaml | kubectl apply -f -
sleep 60
certname=$(kubectl get ManagedCertificate.networking.gke.io/${cluster_name}-managed-cert -o jsonpath='{.status.certificateName}')
status=$?
if [[ $status -eq 0 ]]; then
  echo "Install ssl certificate  ${cluster_name}-managed-cert successfully! The cername is ${certname} "
else
  echo "Install ssl certificate  ${cluster_name}-managed-cert failed!"
  exit 1
fi


# Install LB of the cluster
echo "===================   Install load balancer  ======================="
escaped_frontenddomains=$(echo "$FRONT_DOMAINS" | sed "s/,/\\\,/g")
escaped_frontendapidomains=$(echo "$API_DOMAINS" | sed "s/,/\\\,/g")
escaped_socketdomains=$(echo "$SOCKET_DOMAINS" | sed "s/,/\\\,/g")
escaped_taskdomains=$(echo "$TASK_DOMAINS" | sed "s/,/\\\,/g")
NEG_ZONES=$(gcloud container clusters describe $cluster_name --region=$zone --project=$gcp_project --format=json | jq '.locations' -c | sed -e 's/\[//g' -e 's/\]//g' -e 's/"//g')
escaped_neg_zones=$(echo  $NEG_ZONES | sed -e 's/,/\\\,/g' -e 's/ //g')
execCMD "helm upgrade --install \
        --set GCPName=$gcp_project
        --set Valueone=$cluster_name \
        --set region=$zone \
        --set certname=$certname \
        --set frontendDomains='$escaped_frontenddomains' \
        --set frontendapiDomains='$escaped_frontendapidomains' \
        --set socketDomains='$escaped_socketdomains' \
        --set taskDomains='$escaped_taskdomains' \
        --set neg_zones='$escaped_neg_zones' \
        --set staticFileBucketname=$STATICFILEBUCKETNAME \
        spaces-lb-$cluster_name charts/spaces-lb --wait"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Install load balancer for the cluster $cluster_name successfully!"
else
  echo "Apply virtual service to the cluster $cluster_name failed!"
  exit 1
fi

if [ -z "$STATICFILEBUCKETNAME" ]; then
  echo "After 60 seconds, make bucket as public and set index.html and 404.html"
  sleep 60
  execCMD "gsutil iam ch allUsers:objectViewer gs://$gcp_project-$cluster_name-st"
  status=$?
  if [[ $status -eq 0 ]]; then
    echo "Make the bucket gs://$gcp_project-$cluster_name-st public successfully!"
  else
    echo "Make the bucket gs://$gcp_project-$cluster_name-st public failed"
    exit 1
  fi

  execCMD "gsutil web set -m index.html -e 404.html gs://$gcp_project-$cluster_name-st"
  status=$?
  if [[ $status -eq 0 ]]; then
    echo "Set index.html and 404.html for the bucket gs://$gcp_project-$cluster_name-st successfully!"
  else
    echo "Set index.html and 404.html for the bucket gs://$gcp_project-$cluster_name-st public failed"
    exit 1
  fi
fi
