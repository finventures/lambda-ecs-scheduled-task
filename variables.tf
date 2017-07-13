variable "ecs_cluster_arn" {
    description = "ARN of the ECS cluster to run the deploy task and fin core service within"
}

variable "event_schedule" {
    description = "Schedule to run this task, either in cron format ( 'cron(* * * * ? *)' ) or rate format ( 'rate(5 minutes)' )"
}

variable "task_name" {
    description = "Unique name for the task"
}

variable "command" {
    description = "The command to run"
}

variable "env_short_name" {
    description = "Name of the environment that this task runs on, e.g. staging1. This is used to scope the names of all the resources, so we can create an instance of this module for each environment."
}

variable "lambda_role_arn" {
    description = "Role that the aws lambda function needs to run as"
}

variable "locks_table_name" {
    description = "Name of the dynamodb table to use for locking tasks"
}

variable "task_definition_family" {
    description = "The task definition family that the task will run on"
}

variable "container_name" {
    description = "The name of the container to run the task in"
}

variable "is_enabled" {
    description = "The event schedule is enabled. Changing this default to false will disable all scheduled tasks"
    default = "true"
}

variable "alarm_action_arns" {
    description = "A list of the ARNs of the actions (sns topics) taken when alarm is in an error state"
    default = []
    type = "list"
}

variable "num_lock_failure_alarm_threshold" {
    description = "If a lock for this task fails to be obtained this many times in the time period, send and alert"
    default = "1"
}

variable "num_minutes_lock_failure_alarm_threshold" {
    description = "The number of minutes to evaluate the num_lock_failure_alarm_threshold for alerting"
    default = "1"
}

variable "lock_failure_alarm_treat_missing_data" {
    description = "Sets how the 'failure to obtain lock alarm is to handle missing data points"
    default = "missing"
}
