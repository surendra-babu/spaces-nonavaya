#!/bin/bash
execCMD(){
  echo $1
  eval $1
}


gcp_project="onesnastaging"
cluster_name="artillery-vu"
zone="us-central1-a"

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

gcloud container clusters describe $cluster_name  --zone=$zone --project=$gcp_project --format=json > cluster_info.json

echo "=============== Check the addon of http ==================="
is_http_disabled=$(cat "cluster_info.json" | jq ".addonsConfig.httpLoadBalancing.disabled")
echo "============= httpLoadBalancing  |$is_http_disabled| "
if [[ "$is_http_disabled" = "true" ]]; then
  echo "The cluster didn't start http addon. Install the http addon in this cluster!"
  execCMD "gcloud container clusters update $cluster_name --update-addons='HttpLoadBalancing=ENABLED' --zone=$zone --project=$gcp_project"
fi
