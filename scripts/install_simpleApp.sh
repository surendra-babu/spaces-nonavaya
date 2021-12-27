#!/bin/bash
execCMD(){
  echo $1
  $1
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
execCMD "gcloud container clusters get-credentials $cluster_name --region=$zone --project=$gcp_project"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Connect to the cluster $cluster_name successfully!"
else
  echo "Create to the cluster $cluster_name failed!"
  exit 1
fi


# Check spaces app isinstalled or not
echo "================== User new spaces services =========================="
execCMD "helm status spaces-app"
status=$?
if [[ $status -ne 0 ]]; then
  echo "No spaces app there, delete all resource"
  execCMD "kubectl delete deployment -n $INJECT_NAMESPACES spaces-frontend"
  execCMD "kubectl delete deployment -n $INJECT_NAMESPACES spaces-task"
  execCMD "kubectl delete ConfigMap -n $INJECT_NAMESPACES spaces-configmap-20180220"
  execCMD "kubectl delete HorizontalPodAutoscaler -n $INJECT_NAMESPACES spaces-frontend"
  execCMD "kubectl delete HorizontalPodAutoscaler -n $INJECT_NAMESPACES spaces-task"
  execCMD "kubectl delete Secret -n $INJECT_NAMESPACES spaces-secrets-20180220"
  execCMD "kubectl delete Service -n $INJECT_NAMESPACES spaces-frontend"
  execCMD "kubectl delete Service -n $INJECT_NAMESPACES spaces-task"

  echo "================= Wait for 1 minute to continue =================="
  sleep 60
fi

# Apply virtual service 
echo "================== Apply virtual service ================="
kubectl create namespace socketio-proxy --dry-run=client -o yaml | kubectl apply -f -
execCMD "helm upgrade --install --set spacesNamespace=$INJECT_NAMESPACES --set clustername=$cluster_name virtualservices charts/istio-es-spaces --wait"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Apply virtual service to the cluster $cluster_name successfully!"
else
  echo "Apply virtual service to the cluster $cluster_name failed!"
  exit 1
fi

# Install Flagger
echo "================= Install Flagger =================="
execCMD "helm repo add flagger https://flagger.app"
execCMD "kubectl apply -f https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml"
execCMD "helm upgrade -i flagger flagger/flagger --namespace=istio-system --set crd.create=false --set meshProvider=istio --set metricsServer=http://prometheus.istio-system:9090 --set selectorLabels=role --wait"
kubectl create namespace test --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k https://github.com/fluxcd/flagger//kustomize/tester?ref=main
execCMD "helm upgrade -i --set spacesNamespace=$INJECT_NAMESPACES flagger-es-spaces charts/flagger-es-spaces --wait"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Install Flagger to the cluster $cluster_name successfully!"
else
  echo "Install Flagger to the cluster $cluster_name failed! Still continue "
  exit 1
fi
