#  Copyright 2016 Amazon Web Services, Inc. or its affiliates. All Rights Reserved.
#  This file is licensed to you under the AWS Customer Agreement (the "License").
#  You may not use this file except in compliance with the License.
#  A copy of the License is located at http://aws.amazon.com/agreement/ .
#  This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or implied.
#  See the License for the specific language governing permissions and limitations under the License.

from __future__ import print_function
import boto3
import traceback
from botocore.vendored import requests
import json


SUCCESS = "SUCCESS"
FAILED = "FAILED"


def send(event, context, response_status, response_data, physical_resource_id):
    response_url = event['ResponseURL']

    print(response_url)

    response_body = dict()
    response_body['Status'] = response_status
    response_body['Reason'] = 'See the details in CloudWatch Log Stream: ' + context.log_stream_name
    response_body['PhysicalResourceId'] = physical_resource_id or context.log_stream_name
    response_body['StackId'] = event['StackId']
    response_body['RequestId'] = event['RequestId']
    response_body['LogicalResourceId'] = event['LogicalResourceId']
    response_body['Data'] = response_data

    json_response_body = json.dumps(response_body)

    print("Response body:\n" + json_response_body)

    headers = {
        'content-type': '',
        'content-length': str(len(json_response_body))
    }

    try:
        response = requests.put(response_url, data=json_response_body, headers=headers)
        print("Status code: " + response.reason)
    except Exception as e:
        print("send(..) failed executing requests.put(..): " + str(e))


def lambda_handler(event, context):
    status = SUCCESS
    try:
        print(json.dumps(event))
        if event['RequestType'] == 'Delete':
            tag_key = "kubernetes.io/cluster/%s" % event["ResourceProperties"]["ClusterName"]
            lb_types = [
                ["elb", "LoadBalancerName", "LoadBalancerNames", "LoadBalancerDescriptions", "LoadBalancerName"],
                ["elbv2", "LoadBalancerArn", "ResourceArns", "LoadBalancers", "ResourceArn"]
            ]
            for lt in lb_types:
                elb = boto3.client(lt[0])
                lbs = []
                response = elb.describe_load_balancers()
                while True:
                    lbs += [l[lt[1]] for l in response[lt[3]]]
                    if "NextMarker" in response.keys():
                        response = elb.describe_load_balancers(Marker=response["NextMarker"])
                    else:
                        break
                lbs_to_remove = []
                if lbs:
                    lbs = elb.describe_tags(**{lt[2]: lbs})["TagDescriptions"]
                    for tags in lbs:
                        for tag in tags['Tags']:
                            if tag["Key"] == tag_key and tag['Value'] == "owned":
                                lbs_to_remove.append(tags[lt[4]])
                if lbs_to_remove:
                    for lb in lbs_to_remove:
                        print("removing elb %s" % lb)
                        elb.delete_load_balancer(**{lt[1]: lb})
            ec2 = boto3.client('ec2')
            response = ec2.describe_tags(Filters=[
                {'Name': 'tag:%s' % tag_key, 'Values': ['owned']},
                {'Name': 'resource-type', 'Values': ['security-group']}
            ])
            for t in [r['ResourceId'] for r in response['Tags']]:
                ec2.delete_security_group(GroupId=t)
    except Exception as e:
        status = FAILED
        print(e)
        traceback.print_exc()
    send(event, context, status, {}, '')
