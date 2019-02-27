#!/bin/bash

#

#   This code was written by somckitk@amazon.com.
#   This sample code is provided on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

#



###Global Variables###


#source our configuration file
source /root/install/config

#remove the password after we have read it in
sed -i '/SDH_S_USER_PASS/d' /root/install/config
sed -i '/SDH_VORA_PASS/d'  /root/install/config

#set variables based on which SAP Data Hub version we are installing

if [ "$SDH_VERSION" == "2.4" ]
then
        echo "2.4 - $SDH_VERSION"
else
        echo "2.4.1 - $SDH_VERSION"
fi

export KUBECONFIG="/root/.kube/config"

aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$REGION"

sleep 5

echo "KUBECONFIG = $KUBECONFIG"

#test to see if we can communicate to the EKS cluster
EKS_STATUS=$(kubectl get nodes | wc -l)

EKS_STATUS_COUNT="15"
EKS_STATUS_LOOP="0"

until [ "$EKS_STATUS" -gt 3 ]
do
    sleep 5
    EKS_STATUS=$(kubectl get nodes | wc -l)
    echo "Trying to talk to EKS via kubectl...Status Loop = $EKS_STATUS_LOOP"

    #check to see if we tried too many times
    let EKS_STATUS_LOOP="$EKS_STATUS_LOOP + 1"

    if [ "$EKS_STATUS_LOOP" -eq "$EKS_STATUS_COUNT" ]
    then
        echo "Tried too many times to connect with kubectl...Status Loop = $EKS_STATUS_LOOP -- EXITING"
        exit 1
    fi
done


if [ ! "$EKS_STATUS" -ge 3 ]
then
        echo "Can not communicate with EKS cluster, number of EKS workers nodes = $EKS_STATUS -- EXITING"
        exit 1
fi

#create a default Kubernetes storage class for EKS version <1.11
if [ "$EKS_CLUSTER_VERSION" == "1.10" ]
then
        kubectl apply -f /root/install/storage-class.yaml
        
fi

#download helm
cd /tmp

curl https://storage.googleapis.com/kubernetes-helm/helm-v2.10.0-linux-amd64.tar.gz > helm-v2.10.0-linux-amd64.tar.gz

gzip -fd helm-v2.10.0-linux-amd64.tar.gz

tar -xvf helm-v2.10.0-linux-amd64.tar

cp linux-amd64/helm /usr/bin
chmod 755 /usr/bin/helm

#apply the helm role to our EKS Cluster
kubectl apply -f /root/install/helm.yaml

#initialize helm in our EKS Cluster
helm init --service-account tiller

sleep 15

#HELM_STATUS=$(helm ls)

#look to see if helm is up and running
HELM_POD_STATUS=$(kubectl get pods --all-namespaces | grep tiller | awk '{ print $4 }')

#Define how long to wait for tiller pod
TILLER_LOOP_COUNT="0"
TILLER_LOOP_TOTAL="10"

if [ "$HELM_POD_STATUS" != "Running" ]
then
        until [ "$TILLER_LOOP_COUNT" -ge "TILLER_LOOP_TOTAL" ]
        do
                echo "Waiting for tiller pod to become Running"
                sleep 15
                let TILLER_LOOP_COUNT="$TILLER_LOOP_COUNT + 1"

                #Check to see we have exeucted the TILLER_LOOP_TOTAL, if we have then exit
                if [ "$TILLER_LOOP_COUNT" -eq "TILLER_LOOP_TOTAL" ]
                then
                        echo "Checked for tiller running a total of $TILLER_LOOP_COUNT times, EXITING"
                        exit 1
                fi
        done
else
        echo "tiller pod has correct Running status"
fi


#download the SAP Data Hub software
mkdir /tmp/SDH

aws s3 sync s3://${SDHSwS3BucketName}/${SDHSwS3PrefixName} /tmp/SDH

#validate the download
cd /tmp/SDH
unzip -o *

INSTALL_SH=$(find . -name install.sh)

if [ ! -f "$INSTALL_SH" ]
then
        echo "Can not find install.sh file, $INSTALL_SH -- EXITING"
        exit 1
fi


#Create the ECR repositories needed for the SAP Data Hub installation
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vora-dqp --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vora-dqp-textanalysis --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/spark-datasourcedist --region $REGION
#aws ecr create-repository --repository-name=com.sap.hana.container/base-opensuse42.3-amd64 --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vora-deployment-operator --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/security-operator --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/init-security --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/uaa --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/opensuse-leap --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-vrep --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-auth --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-teardown --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-module-loader --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/app-base --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/flowagent --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/app-base --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vora-license-manager --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-shared-ui --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-ui --region $REGION
#aws ecr create-repository --repository-name=com.sap.datahub.linuxx86_64/vsystem-voraadapter --region $REGION
#aws ecr create-repository --repository-name=elasticsearch/elasticsearch-oss --region $REGION
#aws ecr create-repository --repository-name=fabric8/fluentd-kubernetes --region $REGION
#aws ecr create-repository --repository-name=grafana/grafana --region $REGION
#aws ecr create-repository --repository-name=kibana/kibana-oss --region $REGION
#aws ecr create-repository --repository-name=google_containers/kube-state-metrics --region $REGION
#aws ecr create-repository --repository-name=nginx --region $REGION
#aws ecr create-repository --repository-name=prom/alertmanager --region $REGION
#aws ecr create-repository --repository-name=prom/node-exporter --region $REGION
#aws ecr create-repository --repository-name=prom/prometheus --region $REGION
#aws ecr create-repository --repository-name=prom/pushgateway --region $REGION
#aws ecr create-repository --repository-name=consul --region $REGION
#aws ecr create-repository --repository-name=nats-streaming --region $REGION
#aws ecr create-repository --repository-name=vora/hello-world --region $REGION

#validate that all ECR repos were created
ECR_REPOS=$(aws ecr describe-repositories --region $REGION --output text | wc -l)
ECR_REPOS_COUNT="30"

if [ "$ECR_REPOS" -lt "$ECR_REPOS_COUNT" ]
then
        echo "Not all ECR repositories create. $$ECR_REPOS out of a total of $ECR_REPOS_COUNT created -- EXITING"
        exit 1
fi

#test if the ECR repo has been created and is accessible
aws ecr get-login --no-include-email --region $REGION > /tmp/ecr.sh
ECR_LOGIN=$(bash /tmp/ecr.sh | grep -i "succeeded" )

if [ -z "$ECR_LOGIN" ]
then
        echo "Could not log into the ECR repository -- EXITING"
        exit 1
fi

ECR_NAME=$(aws ecr describe-repositories --region $REGION --output text | tail -1 | awk '{ print $NF }' | awk -F "/" '{ print $1 }')

#start the SAP Data Hub silent installation
#bash "$INSTALL_SH" -n datahub -r "$ECR_NAME" --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=2  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --enable-checkpoint-store no --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME"


bash "$INSTALL_SH" -n datahub -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=2  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --enable-checkpoint-store no --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME"

#validate SAP Data Hub installation

SDH_PODS=$(kubectl get pods -n datahub | wc -l)

if [ "$SDH_PODS" -gt 50 ]
then
        echo "SAP Data Hub installation *successful*. Number of SDH_PODS = $SDH_PODS"
else
        echo "SAP Data Hub installation *NOT* successful. Number of SDH_PODS = $SDH_PODS -- EXITING"
        exit 1      
fi

#remove the password from the execution logs
sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init-cmd.log
sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init.log
