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
            ######## Code goes here
            stack_id = event['RequestProperties']['StackId']
            for repo in ecr_client.list_repos():
                if repo['tag'] == stack_id:
                    for image in ecr_client.describe_images():
                        ecr_client.delete_image(image)
    except Exception as e:
        status = FAILED
        print(e)
        traceback.print_exc()
    send(event, context, status, {}, '')