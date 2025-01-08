import json
import boto3
import os
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2_client = boto3.client('ec2')
ssm_client = boto3.client('ssm')

# Environment variables
INSTANCE_ID = os.environ['INSTANCE_ID']
PARAM_NAME = os.environ.get('PARAM_NAME', 'mcValheimPW')

def get_instance_public_ip(instance_id):
    """Get the public IP address of the instance."""
    reservations = ec2_client.describe_instances(InstanceIds=[instance_id]).get("Reservations")
    logger.info(f"Describe Instances Output: {json.dumps(reservations, default=str)}")
    return reservations[0]['Instances'][0].get('PublicIpAddress')

def get_ssm_parameter(param_name):
    """Get the parameter value from SSM Parameter Store."""
    response = ssm_client.get_parameter(Name=param_name, WithDecryption=True)
    return response['Parameter']['Value']

def get_instance_state(instance_id):
    """Get the current state of the instance."""
    reservations = ec2_client.describe_instances(InstanceIds=[instance_id]).get("Reservations")
    state = reservations[0]['Instances'][0]['State']['Name']
    logger.info(f"Instance {instance_id} state: {state}")
    return state

def start_instance(instance_id, param_name):
    """Start the EC2 instance and return its public IP and password."""
    state = get_instance_state(instance_id)
    if state == 'running':
        public_ip = get_instance_public_ip(instance_id)
        password = get_ssm_parameter(param_name)
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps({'message': 'Servidor já ligado', 'public_ip': public_ip, 'port': 2456, 'password': password, 'status': 'ON'})
        }
    
    ec2_client.start_instances(InstanceIds=[instance_id])
    logger.info(f"Instance {instance_id} starting")
    
    return {
        'statusCode': 202,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        },
        'body': json.dumps({'message': 'Iniciando servidor', 'status': 'STARTING'})
    }

def stop_instance(instance_id):
    """Stop the EC2 instance."""
    state = get_instance_state(instance_id)
    if state == 'stopped':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps({'message': 'Servidor já desligado', 'status': 'OFF'})
        }
    
    ec2_client.stop_instances(InstanceIds=[instance_id])
    logger.info(f"Instance {instance_id} stopping")
    
    return {
        'statusCode': 202,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        },
        'body': json.dumps({'message': 'Desligando servidor', 'status': 'STOPPING'})
    }

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    try:
        body = json.loads(event.get('body', '{}'))
        action = body.get('action')
    except json.JSONDecodeError as e:
        logger.error("Invalid JSON format")
        return {
            'statusCode': 400,
            'body': json.dumps('Invalid JSON format')
        }

    try:
        if action == 'start':
            return start_instance(INSTANCE_ID, PARAM_NAME)
        elif action == 'stop':
            return stop_instance(INSTANCE_ID)
        elif action == 'status':
            state = get_instance_state(INSTANCE_ID)
            if state == 'running':
                public_ip = get_instance_public_ip(INSTANCE_ID)
                password = get_ssm_parameter(PARAM_NAME)
                return {
                    'statusCode': 200,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Methods': 'POST, OPTIONS',
                        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
                    },
                    'body': json.dumps({'message': 'Servidor ligado', 'public_ip': public_ip, 'port': 2456, 'password': password, 'status': 'ON'})
                }
            else:
                return {
                    'statusCode': 200,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Methods': 'POST, OPTIONS',
                        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
                    },
                    'body': json.dumps({'message': 'Servidor desligado', 'status': 'OFF'})
                }
        else:
            logger.error(f"Invalid action: {action}")
            return {
                'statusCode': 400,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
                },
                'body': json.dumps('Invalid action')
            }
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps(f"Error: {str(e)}")
        }