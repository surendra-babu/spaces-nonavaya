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

# Change master network ports
echo "================== add port 15017 to master network =================="
network_name=$(gcloud compute firewall-rules list --filter="name~testcluster" --project=$gcp_project --format=json | jq '.[0].name' | sed 's/"//g')
execCMD "gcloud compute firewall-rules update $network_name --allow tcp:10250,tcp:443,tcp:15017,tcp:8080,tcp:15000 --project=$gcp_project"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Add 15017 to network $network_name successfully!"
else
  echo "Add 15017 to network $network_name failed!"
  exit 1
fi

# Init operator
echo "==================   Init Istio Operator ========================="
execCMD "istioctl operator init"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Init Istio Operator $cluster_name successfully!"
else
  echo "Init Istio Operator $cluster_name failed!"
  exit 1
fi

# Apply operator in the cluster
echo "==================   Install isio and istiocontrolplane  ========================="
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
rm -f ./isto_oper_overwrite.yaml
echo "frontend_neg: frontend-$cluster_name" >> ./isto_oper_overwrite.yaml
echo "socketio_neg: socketio-$cluster_name" >> ./isto_oper_overwrite.yaml
echo "task_neg: task-$cluster_name" >> ./isto_oper_overwrite.yaml

if [ "$INJECT_NAMESPACES" == "production" ]; then
  echo "ingressGatewyasAutoscalMin: 4" >> ./isto_oper_overwrite.yaml
  echo "ingressGatewyasAutoscalMax: 16" >> ./isto_oper_overwrite.yaml
  echo "pilotAutoscalMin: 2" >> ./isto_oper_overwrite.yaml
  echo "pilotAutoscalMax: 8" >> ./isto_oper_overwrite.yaml
fi

cat ./isto_oper_overwrite.yaml 

execCMD "helm upgrade --install -f ./isto_oper_overwrite.yaml spaces-operator charts/spaces-operator --wait"
# Checking status of the spaces-istiocontrolplane 
echo "==================   Check status of spaces-istiocontrolplane   ========================="
statusResult=0
for i in {1..6}
do
   sleep 60
   checkResult=$(kubectl get IstioOperator spaces-istiocontrolplane  -n istio-system -o json | jq ".status.status")
   if [[ $checkResult == *"HEALTHY"* ]]; then
     statusResult=1
     break
   else
     echo "Get the checking result $checkResult"
   fi
done

if [[ $statusResult -eq 0 ]]; then
  exit 1
fi

echo "==================   Install isio addons  ========================="
execCMD "kubectl apply -f /istio/samples/addons/"
status=$?
if [[ $status -ne 0 ]]; then
  # For brand new cluster, it may need run install addons twice for MonitoringDashboard need install first.
  echo "Init Istio addons $cluster_name failed, try again in 60 seconds"
  sleep 60 
  execCMD "kubectl apply -f /istio/samples/addons/"
fi

status=$?
if [[ $status -eq 0 ]]; then
  echo "Init Istio addons $cluster_name successfully!"
else
  echo "Init Istio addons $cluster_name failed!"
  exit 1
fi

echo "================  Inject istio into a namespace ===================="
if [[ $INJECT_NAMESPACES != 'default' ]]; then
  kubectl create namespace $INJECT_NAMESPACES --dry-run=client -o yaml | kubectl apply -f -
fi
execCMD "kubectl label namespace $INJECT_NAMESPACES istio-injection=enabled --overwrite"
status=$?
if [[ $status -eq 0 ]]; then
  echo "Inject istio to namespaces $INJECT_NAMESPACES successfully!"
else
  echo "Inject istio to namespaces $INJECT_NAMESPACES failed!"
  exit 1
fi

