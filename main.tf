# This module sets up a Lambda function to run a scheduled task on ECS

resource "aws_lambda_function" "scheduled_task" {
    function_name = "scheduled-task-${var.env_short_name}-${var.task_name}"
    description = "Scheduled task ${var.task_name} in ${var.env_short_name} environment"
    filename = "${path.module}/dist/scheduled_task.zip"
    role = "${var.lambda_role_arn}"
    handler = "run_scheduled_task.event_handler"
    runtime = "python2.7"
    memory_size = 128
    timeout = 300
    publish = "true"
    # We zip the file out of band, when the value changes then this hash tells terraform to update
    # the lambda function version.
    source_code_hash = "${base64sha256(file("${path.module}/dist/scheduled_task.zip"))}"
    environment {
        variables = {
            ECS_CLUSTER_ARN = "${var.ecs_cluster_arn}"
            SCHEDULED_TASK_NAME = "${var.task_name}"
            SCHEDULED_TASK_COMMAND = "${var.command}"
            ECS_TASK_DEFINITION_FAMILY = "${var.task_definition_family}"
            CONTAINER_NAME = "${var.container_name}"
            ENVIRONMENT_NAME = "${var.env_short_name}"
            DYNAMODB_TABLE_NAME = "${var.locks_table_name}"
        }
    }
    lifecycle {
        ignore_changes = ["filename"]
    }
}

resource "aws_cloudwatch_event_rule" "scheduled_task_cron" {
    name = "scheduled-task-${var.env_short_name}-${var.task_name}"
    description = "Triggers ${var.task_name} in ${var.env_short_name} on schedule ${var.event_schedule}"
    is_enabled = "${var.is_enabled}"
    schedule_expression = "${var.event_schedule}"
}

resource "aws_cloudwatch_event_target" "trigger_scheduled_task_lambda_function_on_cron" {
    rule = "${aws_cloudwatch_event_rule.scheduled_task_cron.name}"
    arn = "${aws_lambda_function.scheduled_task.arn}"
}

resource "aws_lambda_permission" "lambda_scheduled_task_cron_trigger_to_ecs" {
    statement_id = "allow-cron-trigger-for-lambda-scheduled-task-${var.env_short_name}-${var.task_name}"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.scheduled_task.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.scheduled_task_cron.arn}"
}

resource "aws_cloudwatch_metric_alarm" "scheduled_task_lambda_failure_alarm" {
    alarm_name                = "Lambda ${aws_lambda_function.scheduled_task.function_name} Failure Alarm"
    comparison_operator       = "GreaterThanThreshold"
    evaluation_periods        = "1"
    metric_name               = "Errors"
    namespace                 = "AWS/Lambda"
    dimensions {
      FunctionName = "${aws_lambda_function.scheduled_task.function_name}"
    }
    period                    = "60"
    statistic                 = "Sum"
    threshold                 = "0"
    alarm_description         = "This alarm is set off if the lambda function ${aws_lambda_function.scheduled_task.function_name} fails once within a minute"
    insufficient_data_actions = []
    alarm_actions = ["${var.alarm_action_arns}"]
}

resource "aws_cloudwatch_metric_alarm" "scheduled_task_failure_to_obtain_lock_alarm" {
    alarm_name                = "Scheduled Task ${var.task_name} on ${var.env_short_name} Failure to Obtain Lock"
    comparison_operator       = "GreaterThanOrEqualToThreshold"
    evaluation_periods        = "${var.num_minutes_lock_failure_alarm_threshold}"
    metric_name               = "lock-not-obtained"
    namespace                 = "Scheduled Tasks"
    dimensions {
      "By Environment" = "${var.env_short_name}"
      "By Task Name"   = "${var.task_name}"
    }
    period                    = "60"
    statistic                 = "Sum"
    threshold                 = "${var.num_lock_failure_alarm_threshold}"
    alarm_description         = "Fails when the task ${var.task_name} on ${var.env_short_name} env fails to obtain a lock ${var.num_lock_failure_alarm_threshold} times in ${var.num_minutes_lock_failure_alarm_threshold} minutes"
    alarm_actions             = ["${var.alarm_action_arns}"]
    treat_missing_data        = "${var.lock_failure_alarm_treat_missing_data}"
    insufficient_data_actions = []
}
