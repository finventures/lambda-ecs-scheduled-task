from time import sleep
import boto3
import os


def event_handler(event, context):
    ecs_client = boto3.client('ecs')
    dynamodb_client = boto3.client('dynamodb')

    cluster_arn = os.environ['ECS_CLUSTER_ARN']
    task_definition_family = os.environ['ECS_TASK_DEFINITION_FAMILY']
    container_name = os.environ['CONTAINER_NAME']
    task_name = os.environ['SCHEDULED_TASK_NAME']
    env_name = os.environ['ENVIRONMENT_NAME']  # staging1, staging2, etc
    dynamodb_table_name = os.environ['DYNAMODB_TABLE_NAME']
    command = os.environ['SCHEDULED_TASK_COMMAND']

    # Set by default by Lambda
    # (http://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html)
    aws_region = os.environ['AWS_REGION']
    function_name = os.environ['AWS_LAMBDA_FUNCTION_NAME']

    command = "/usr/local/bin/in_s3_env.sh {}".format(command)

    task_command = [
        '/usr/local/bin/scheduled_task_runner.py',
        '--task_name', task_name,
        '--env_name', env_name,
        '--dynamodb_table_name', dynamodb_table_name,
        '--region', aws_region,
        command,
    ]

    maintenance_mode_key = "{}|maintenance-mode".format(env_name)
    if maintenance_mode_on(dynamodb_client, dynamodb_table_name, maintenance_mode_key):
        print("Maintenance mode ON. Exiting task {}".format(task_name))
        return

    request_id = context.aws_request_id
    task_definition = get_task_definition(ecs_client, task_definition_family)
    print("Running task {} on cluster {} with command {}".format(
        task_definition, cluster_arn, ' '.join(task_command)))

    response = ecs_client.run_task(
        cluster=cluster_arn,
        taskDefinition=task_definition,
        startedBy="{}/{}".format(function_name, request_id)[0:36],
        overrides={'containerOverrides': [
            {
                'name': container_name,
                'command': task_command,
            }
        ]}
    )

    print(response)
    if response['failures']:
        arns_and_reasons = ', '.join(
                ["{}: {}".format(f['arn'], f['reason']) for f in response['failures']]
                )
        raise RuntimeError("Failure for task name {}; {}".format(task_name, arns_and_reasons))

    task = response['tasks'][0]
    if task['lastStatus'] == 'PENDING':
        poll_while_pending(context, ecs_client, cluster_arn, task['taskArn'])

    return {"completed": True}


def maintenance_mode_on(dynamodb_client, dynamodb_table_name, maintenance_mode_key):
    """
    If maintenance mode is on, then the key `maintenance_mode_key` will be present
    and an Item will be returned in the response to `get_item`. If there is no
    item, that key will be absent from the response.
    """
    response = dynamodb_client.get_item(
            TableName=dynamodb_table_name,
            Key={'LockType': {'S': maintenance_mode_key}},
            ConsistentRead=True,
    )
    return 'Item' in response


def get_task_definition(client, family):
    task_definition = client.describe_task_definition(taskDefinition=family)
    if not task_definition:
        raise ValueError("Unable to find task definition corresponding to {}".format(family))
    revision = task_definition['taskDefinition']['revision']
    return "{}:{}".format(family, revision)


def poll_while_pending(context, client, cluster_arn, task_arn):
    # raise if not running and there are only 10 seconds left before timing out
    THRESHOLD_MILLIS = 10 * 1000
    while True:
        response = client.describe_tasks(cluster=cluster_arn, tasks=[task_arn])
        print(response)

        if response['failures']:
            # For some reason we sometimes get a 'MISSING' status, perhaps when in between statuses?
            # https://github.com/boto/boto3/issues/842
            if response['failures'][0]['reason'] == 'MISSING':
                continue
            arns_and_reasons = ', '.join([
                "{}: {}".format(f['arn'], f['reason']) for f in response['failures']
            ])
            raise RuntimeError("Failure for task name {}; {}".format(task_arn, arns_and_reasons))
        task = response['tasks'][0]
        if task['lastStatus'] != 'PENDING':
            break
        remain_millis = context.get_remaining_time_in_millis()
        print("{} remaining milliseconds until function times out....".format(remain_millis))
        if remain_millis < THRESHOLD_MILLIS:
            raise RuntimeError("Task {} never started".format(task_arn))

        print("sleeping 1 second")
        sleep(1)
