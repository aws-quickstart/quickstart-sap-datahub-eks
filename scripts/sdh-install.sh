#!/bin/bash

#

#   This sample code is provided on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

#



###BEGIN-Global Variables###
#define global file locations
CONFIG_FILE="/root/install/config"
SDH_SW_TARGET="/tmp/SDH"
HOME_DIR=$(grep root /etc/passwd | cut -d: -f6)
export HOME="$HOME_DIR"

#this is the min. size the s/w should be when downloaded
SDH_TOTAL_SIZE="1840408"

#this is the min. number of ECR repositories that should be created
ECR_REPOS_COUNT="30"

#this is the min. number of SDH Kubernetes pods that should be running
SDH_TOTAL_PODS="30"

#define some YAML files needed for Kubernetes 
HELM_YAML="/root/install/helm.yaml"
INGRESS_YAML="/root/install/ingress.yaml"
STORAGE_YAML="/root/install/storage-class.yaml"
###END-Global Variables###

#install nslookup utility
yum -y install bind-utils

#tune networking for faster downloads
sysctl -w net.core.rmem_default=1677721600
sysctl -w net.core.rmem_max=1677721600
sysctl -w net.core.rmem_default=167772160
sysctl -w net.core.wmem_max=1677721600
sysctl -w net.core.wmem_default=167772160
sysctl -w net.core.optmem_max=167772160
sysctl -w net.ipv4.tcp_rmem="1677721600 1677721600 1677721600"
sysctl -w net.ipv4.tcp_wmem="1677721600 1677721600 1677721600"
sysctl -w net.ipv4.tcp_mem="1677721600 1677721600 1677721600"
sysctl -w net.ipv4.udp_mem="1677721600 1677721600 1677721600"


sed -i '/config/d' "$CONFIG_FILE"

#source our configuration file
source "$CONFIG_FILE"

#remove the password and access keys from the config file after we have read it in
sed -i '/SDH_S_USER_PASS/d' "$CONFIG_FILE"
sed -i '/SDH_VORA_PASS/d'  "$CONFIG_FILE"
sed -i '/SDH_ACCESS_KEY/d' "$CONFIG_FILE"
sed -i '/SDH_SECRET_ACCESS_KEY/d'  "$CONFIG_FILE"

#set variables based on which SAP Data Hub version we are installing

if [ "$SDH_VERSION" == "2.4" ]
then
        echo "2.4 - $SDH_VERSION"

        if [ "$EKS_CLUSTER_VERSION" == "1.11" ]
        then
                echo "The combination of SAP Data Hub version "$SDH_VERSION" and EKS version "$EKS_CLUSTER_VERSION" is *NOT* Supported by SAP -- EXITING"
                echo "Choose SAP Data Hub version *2.4.1* if you want to run EKS version *1.11*"
                echo "Check the SAP Data Hub Platform Availability Matrix for supported combinations"
                echo "https://support.sap.com/content/dam/launchpad/en_us/pam/pam-essentials/SAP_Data_Hub_2_PAM.pdf"
                bash -x /root/install/signal-final-status.sh 1 "The combination of SAP Data Hub version "$SDH_VERSION" and EKS version "$EKS_CLUSTER_VERSION" is *NOT* Supported by SAP -- EXITING"
                exit 1
        fi
else
        echo "2.4.1 - $SDH_VERSION"
fi

#clean-up files
dos2unix /root/install/signal-final-status.sh

#setup the kubectl configuration
export KUBECONFIG="/root/.kube/config"

aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$REGION"

sleep 5

echo "KUBECONFIG = $KUBECONFIG"

#download the SAP Data Hub software
mkdir "$SDH_SW_TARGET"

#aws s3 sync s3://${SDHSwS3BucketName}/${SDHSwS3PrefixName} "$SDH_SW_TARGET"

aws s3 cp s3://${SDHSwS3BucketName}/${SDHSwS3PrefixName} "$SDH_SW_TARGET" --recursive

#try to re-download the files if there is an issue with downloaded file size
SDH_DNL_SIZE=$(du -sk "$SDH_SW_TARGET" | cut -f1)


if [ ${SDH_DNL_SIZE} -le ${SDH_TOTAL_SIZE} ]
then
        echo "Retrying S3 download..."
        #aws s3 sync s3://${SDHSwS3BucketName}/${SDHSwS3PrefixName} "$SDH_SW_TARGET"
        aws s3 cp s3://${SDHSwS3BucketName}/${SDHSwS3PrefixName} "$SDH_SW_TARGET" --recursive

fi

#validate the download
cd "$SDH_SW_TARGET"
unzip -o *

INSTALL_SH=$(find . -name install.sh)

if [ ! -f "$INSTALL_SH" ]
then
        echo "Can not find install.sh file, $INSTALL_SH -- EXITING"
        bash -x /root/install/signal-final-status.sh 1 "Can not find install.sh file, $INSTALL_SH -- EXITING"
        exit 1
fi


#test to see if we can communicate to the EKS cluster
EKS_STATUS=$(kubectl get nodes | wc -l)

EKS_STATUS_COUNT="15"
EKS_STATUS_LOOP="0"

until [ "$EKS_STATUS" -ge 3 ]
do
    sleep 5
    EKS_STATUS=$(kubectl get nodes | wc -l)
    echo "Trying to talk to EKS via kubectl...Status Loop = $EKS_STATUS_LOOP"

    #check to see if we tried too many times
    let EKS_STATUS_LOOP="$EKS_STATUS_LOOP + 1"

    if [ "$EKS_STATUS_LOOP" -eq "$EKS_STATUS_COUNT" ]
    then
        echo "Tried too many times to connect with kubectl...Status Loop = $EKS_STATUS_LOOP -- EXITING"
        bash -x /root/install/signal-final-status.sh 1 "Tried too many times to connect with kubectl...Status Loop = $EKS_STATUS_LOOP -- EXITING"
        exit 1
    fi
done


if [ ! "$EKS_STATUS" -ge 3 ]
then
        echo "Can not communicate with EKS cluster, number of EKS workers nodes = $EKS_STATUS -- EXITING"
        bash -x /root/install/signal-final-status.sh 1 "Can not communicate with EKS cluster, number of EKS workers nodes = $EKS_STATUS -- EXITING"
        exit 1
fi

#create a default Kubernetes storage class for EKS version <1.11
#if [ "$EKS_CLUSTER_VERSION" == "1.10" ]
#then
#        kubectl apply -f "$STORAGE_YAML"
        
#fi

#download helm
cd /tmp

#match the helm version to the EKS version
if [ "$EKS_CLUSTER_VERSION" == "1.12" ]
then
        curl https://storage.googleapis.com/kubernetes-helm/helm-v2.12.0-linux-amd64.tar.gz > helm-v2.10.0-linux-amd64.tar.gz
        
fi

if [ "$EKS_CLUSTER_VERSION" == "1.11" ]
then
        curl https://storage.googleapis.com/kubernetes-helm/helm-v2.11.0-linux-amd64.tar.gz > helm-v2.11.0-linux-amd64.tar.gz

        
fi

#unpack and copy the helm executable
gzip -fd helm-*.gz

tar -xvf helm-*.tar

cp linux-amd64/helm /usr/bin
chmod 755 /usr/bin/helm

#apply the helm role to our EKS Cluster
kubectl apply -f $HELM_YAML

#initialize helm in our EKS Cluster
helm init --service-account tiller

sleep 15

#the output of the helm ls command should actually be nothing
HELM_LS_STATUS=$(helm ls)

if [ ! -z "$HELM_LS_STATUS" ]
then
        echo "helm ls command is not empty, need to recheck helm ls again"
fi

#look to see if helm is up and running
HELM_POD_STATUS=$(kubectl get pods --all-namespaces | grep tiller | awk '{ print $4 }')

#Define how long to wait for tiller pod
TILLER_LOOP_COUNT="0"
TILLER_LOOP_TOTAL="10"

if [ "$HELM_POD_STATUS" != "Running" ]
then
        until [[ "$TILLER_LOOP_COUNT" -ge "TILLER_LOOP_TOTAL" ]]
        do
                echo "Waiting for tiller pod to become Running"
                sleep 15
                let TILLER_LOOP_COUNT="$TILLER_LOOP_COUNT + 1"

                #check tiller status again
                HELM_POD_STATUS=$(kubectl get pods --all-namespaces | grep tiller | awk '{ print $4 }')

                #Check to see we have exeucted the TILLER_LOOP_TOTAL, if we have then exit
                if [[ "$TILLER_LOOP_COUNT" -eq "TILLER_LOOP_TOTAL" ]]
                then
                        echo "Checked for tiller running a total of $TILLER_LOOP_COUNT times, EXITING"
                        bash -x /root/install/signal-final-status.sh 1 "Checked for tiller running a total of $TILLER_LOOP_COUNT times, EXITING"
                        exit 1
                fi
        done
else
        echo "tiller pod has correct Running status"
fi


#The below is simply to document the necessary ECR repositories needed by the SAP Data Hub installation process
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

if [ "$SDH_CREATEECR" == "true" ]
then
    #tag the ECR repositories
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vora-dqp --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vora-dqp-textanalysis --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/spark-datasourcedist --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.hana.container/base-opensuse42.3-amd64 --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vora-deployment-operator --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/security-operator --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/init-security --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/uaa --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/opensuse-leap --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-vrep --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-auth --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-teardown --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-module-loader --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/app-base --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/flowagent --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/app-base --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vora-license-manager --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-shared-ui --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-ui --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-voraadapter --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/elasticsearch/elasticsearch-oss --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/fabric8/fluentd-kubernetes --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/grafana/grafana --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/kibana/kibana-oss --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/google_containers/kube-state-metrics --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/nginx --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/prom/alertmanager --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/prom/node-exporter --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/prom/prometheus --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/prom/pushgateway --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/consul --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/nats-streaming --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/vora/hello-world --tags Key=stack,Value=${STACK_ID}  --region $REGION
    #New repos with SDH 2.50
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/hello-sap --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.bds.docker/storagegateway --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/auth-proxy --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/dq-integration --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/elasticsearch --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/flowagent-codegen --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/flowagent-operator --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/flowagent-service --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/fluentd --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/grafana --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/kibana --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/kube-state-metrics --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/nats --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/node-exporter --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/prometheus --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/pushgateway --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vflow-python36 --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsolution-golang --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsolution-hana_replication --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsolution-ml-python --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsolution-sapjvm --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsolution-streaming --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsolution-textanalysis --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/com.sap.datahub.linuxx86_64/vsystem-hana-init --tags Key=stack,Value=${STACK_ID}  --region $REGION
    aws ecr tag-resource --resource-arn arn:aws:ecr:${REGION}:${AWS_ACCT}:repository/kaniko-project/executor --tags Key=stack,Value=${STACK_ID}  --region $REGION
fi


#validate that all ECR repos were created
ECR_REPOS=$(aws ecr describe-repositories --region $REGION --output text | wc -l)


if [ "$ECR_REPOS" -lt "$ECR_REPOS_COUNT" ]
then
        echo "Not all ECR repositories create. $$ECR_REPOS out of a total of $ECR_REPOS_COUNT created -- EXITING"
        bash -x /root/install/signal-final-status.sh 1 "Not all ECR repositories create. $$ECR_REPOS out of a total of $ECR_REPOS_COUNT created -- EXITING"
        exit 1
fi

#test if the ECR repo has been created and is accessible
aws ecr get-login --no-include-email --region $REGION > /tmp/ecr.sh
ECR_LOGIN=$(bash /tmp/ecr.sh | grep -i "succeeded" )

if [ -z "$ECR_LOGIN" ]
then
        echo "Could not log into the ECR repository -- EXITING"
        bash -x /root/install/signal-final-status.sh 1 "Could not log into the ECR repository -- EXITING"
        exit 1
fi

ECR_NAME=$(aws ecr describe-repositories --region $REGION --output text | tail -1 | awk '{ print $NF }' | awk -F "/" '{ print $1 }')

#cd to the s/w location
cd "$SDH_SW_TARGET" 

if [ "$SDH_INSTALL" != "true" ]
then
        echo "SDH_INSTALL is set to $SDH_INSTALL. EXITING"
        bash -x /root/install/signal-final-status.sh 0 "SDH_INSTALL is set to $SDH_INSTALL. Provisioning is complete."
        exit 0
else

        if [ "$SDH_ENABLE_CHECKPOINT" == "true" ]
        then
            #enable below for checkpoint store and ECR role integration
            if [ "$SDH_S_USER_TYPE" == "T" ]
            then
                if [ "$SDH_VERSION" == "2.5" ]
                then
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=1  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0'  --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store yes --checkpoint-store-type s3 --validate-checkpoint-store no --checkpoint-store-connection "https://s3.amazonaws.com/${SDH_CHECKPOINT_STORE}/checkpoint&AccessKey=${SDH_ACCESS_KEY}&SecretAccessKey=${SDH_SECRET_ACCESS_KEY}&Region=${REGION}" 
                else
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=1  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0' --enable-diagnostic-persistency yes --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store yes --checkpoint-store-type s3 --validate-checkpoint-store no --checkpoint-store-connection "https://s3.amazonaws.com/${SDH_CHECKPOINT_STORE}/checkpoint&AccessKey=${SDH_ACCESS_KEY}&SecretAccessKey=${SDH_SECRET_ACCESS_KEY}&Region=${REGION}" 
                fi
            else
                if [ "$SDH_VERSION" == "2.5" ]
                then
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=2  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0' --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store yes --checkpoint-store-type s3 --validate-checkpoint-store no --checkpoint-store-connection "https://s3.amazonaws.com/${SDH_CHECKPOINT_STORE}/checkpoint&AccessKey=${SDH_ACCESS_KEY}&SecretAccessKey=${SDH_SECRET_ACCESS_KEY}&Region=${REGION}" 
                else
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=2  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0' --enable-diagnostic-persistency yes --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store yes --checkpoint-store-type s3 --validate-checkpoint-store no --checkpoint-store-connection "https://s3.amazonaws.com/${SDH_CHECKPOINT_STORE}/checkpoint&AccessKey=${SDH_ACCESS_KEY}&SecretAccessKey=${SDH_SECRET_ACCESS_KEY}&Region=${REGION}" 
                fi
            fi
        else
            if [ "$SDH_S_USER_TYPE" == "T" ]
            then
            #enable below for ECR role integration
                if [ "$SDH_VERSION" == "2.5" ]
                then
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=1  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0'  --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store no  
                else
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=1  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0' --enable-diagnostic-persistency yes --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store no  
                fi
            else
                if [ "$SDH_VERSION" == "2.5" ]
                then
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=2  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0'  --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store no  
                else
                    bash "$INSTALL_SH" -n "$SDH_NAME_SPACE" -r "$ECR_NAME" --sap-registry=73554900100900002861.docker.repositories.sapcdn.io --sap-registry-login-username "$SDH_S_USERID"  --sap-registry-login-password "$SDH_S_USER_PASS"  --sap-registry-login-type=2  --vora-system-password "$SDH_VORA_PASS" --vora-admin-username admin --vora-admin-password "$SDH_VORA_PASS" -a --non-interactive-mode --interactive-security-configuration no -c --cert-domain "$SDH_CERT_DOMAIN_NAME" -e vora-cluster.components.dlog.replicationFactor='1'  -e vora-cluster.components.dlog.standbyFactor='0' --enable-diagnostic-persistency yes --vflow-aws-iam-role="$SDH_IAM_ROLE_ARN" --enable-checkpoint-store no  
                fi
            fi
        fi
        #create custom cert for the Ingress controller
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=*${SDH_CERT_DOMAIN_NAME}"
        kubectl -n $SDH_NAME_SPACE create secret tls vsystem-tls-certs --key /tmp/tls.key --cert /tmp/tls.crt


        #deploy the Ingress controller
        #for a public internet-facing ELB
        if [ "$SDH_ELB_PRIVPUB" == "PUBLIC" ]
        then
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/service-l4.yaml
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/patch-configmap-l4.yaml
        fi

        #for private ELB
        if [ "$SDH_ELB_PRIVPUB" == "PRIVATE" ]
        then
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml
                kubectl apply -f /root/install/private-elb.yaml
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/patch-configmap-l4.yaml
        fi

        
        #wait for the ELB to be created by the service-14.yaml
        ELB_STATUS=$(kubectl get svc --all-namespaces | grep -i nginx | awk '{ print $5 }')

        ELB_LOOP_TOTAL="15"
        ELB_LOOP_COUNT="0"

        while [ "$ELB_STATUS" == "<pending>" ]
        do
                sleep 30
                let ELB_LOOP_COUNT="$ELB_LOOP_COUNT + 1"
                if [[ "$ELB_LOOP_COUNT" -ge "$ELB_LOOP_TOTAL" ]]
                then
                        echo "The ELB is not available -- EXITING"
                        bash -x /root/install/signal-final-status.sh 1 "The ELB is not available STATUS = $ELB_STATUS -- EXITING"
                        exit 1      
        
                fi
                ELB_STATUS=$(kubectl get svc --all-namespaces | grep -i ngi | awk '{ print $5 }')
        done

        #tag the ELB
        #ELB_NAME=$(echo "$ELB_STATUS" | cut -d"." -f 1 | cut -d"-" -f 1)

        #describe load-balancers and find our load-balancer
        if [ "$SDH_ELB_PRIVPUB" == "PUBLIC" ]
        then
                ELB_NAME=$(aws elb describe-load-balancers --region $REGION --output text | grep "$ELB_STATUS" | awk '{ print $6 }')
        fi

        #for private ELB
        if [ "$SDH_ELB_PRIVPUB" == "PRIVATE" ]
        then
                ELB_NAME=$(aws elb describe-load-balancers --region $REGION --output text | grep "$ELB_STATUS" | awk '{ print $5 }')
        fi


        aws elb add-tags --load-balancer-names "$ELB_NAME" --tags Key=stack,Value=${STACK_ID}  --region $REGION

        #validate the ELB is tagged
        ELB_TAG=$(aws elb describe-tags --load-balancer-names "$ELB_NAME" --region $REGION --output text | grep stack | awk '{print $3}')

        if [ -z "$ELB_TAG" ]
        then
            echo "Could not tag the ELB -- EXITING"
            bash -x /root/install/signal-final-status.sh 1 "Could not tag the ELB -- EXITING"
            exit 1
        fi

        #confiugre the ingress.yaml file        
        sed -i "/MYHOSTDOMAIN1/ c\  - host: ${SDH_CERT_DOMAIN_NAME}"  "$INGRESS_YAML"
        sed -i "/MYHOSTDOMAIN2/ c\    - ${SDH_CERT_DOMAIN_NAME}"      "$INGRESS_YAML"

        #delete any existing ingress first
        kubectl delete ing vsystem -n "$SDH_NAME_SPACE"

        sleep 15

        #create the Ingress
        kubectl apply -f "$INGRESS_YAML" -n "$SDH_NAME_SPACE"

        sleep 30

        #validate the ingress
        SDH_INGRESS_COUNT=$(kubectl get ing -n "$SDH_NAME_SPACE" | grep vsystem | wc -l)
        SDH_INGRESS_NAME=$(kubectl get ing -n "$SDH_NAME_SPACE" | grep vsystem | awk '{ print $1 }' )

        if [ "$SDH_INGRESS_COUNT" -ge 1 ]
        then
                echo "The ingress $SDH_INGRESS_NAME was created successfully"
        else
                echo "The ingress $SDH_INGRESS_NAME was *NOT* created successfully"
                bash -x /root/install/signal-final-status.sh 1 "The ingress $SDH_INGRESS_NAME was *NOT* created successfully - EXITING. Please log into your SDH Install host and check the installation"
                #remove the password from the execution logs
                #sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init-cmd.log
                #sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init.log
                exit 1      

        fi

        sleep 30

        #lookup the IP Address of the ELB associated with the Kubernetes Ingress
        ELB_DNS_NAME=$(kubectl describe ing -n "$SDH_NAME_SPACE" | grep Address | awk '{ print $2 }')
        
        sleep 15

        ELB_IP_ADDRESS=$(nslookup "$ELB_DNS_NAME" | grep Address | grep -v "#" | awk '{ print $2 }' | tail -1)

        #check if we have a good IP address
        ELB_LOOP_IP_COUNT="0"
        ELB_LOOP_IP_TOTAL="10"

        if [ -z "$ELB_IP_ADDRESS" ]
        then
                #IP address is empty, retrying
                let ELB_LOOP_IP_COUNT="$ELB_LOOP_IP_COUNT + 1"
                if [[ "$ELB_LOOP_IP_COUNT" -ge "$ELB_LOOP_IP_TOTAL" ]]
                then
                        echo "The ELB IP Address is not available."
        
                fi
                sleep 15
                ELB_IP_ADDRESS=$(nslookup "$ELB_DNS_NAME" | grep Address | grep -v "#" | awk '{ print $2 }' | tail -1)
        fi

        #validate SAP Data Hub installation
        SDH_PODS=$(kubectl get pods -n  "$SDH_NAME_SPACE" | wc -l)

        if [ "$SDH_PODS" -ge "$SDH_TOTAL_PODS" ]
        then
                echo "SAP Data Hub installation *successful*. Number of SDH_PODS = $SDH_PODS"
                bash -x /root/install/signal-final-status.sh "0" "SAP Data Hub installation successful."
                #remove the password from the execution logs
                #sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init-cmd.log
                #sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init.log

        else
                echo "SAP Data Hub installation *NOT* successful. Number of SDH_PODS = $SDH_PODS -- EXITING"
                bash -x /root/install/signal-final-status.sh "1" "SAP Data Hub installation *NOT* successful -- EXITING"
                #remove the password from the execution logs
                #sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init-cmd.log
                #sed -i '/${SDH_S_USER_PASS}/d' /var/log/cfn-init.log
                exit 1      
        fi


fi
