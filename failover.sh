#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===

REGION="eu-central-1"
LOGFILE="failover.log"
SECRET_ARN=$(terraform output -raw secret_arn)
REPLICA_IDENTIFIER=$(terraform output -raw read_replica_id)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_id)
ECS_SERVICE=$(terraform output -raw ecs_service_name)
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)

echo "Starting DR failover at $(date)" > "$LOGFILE"

# === Extract Task Family from ARN ===
TASK_FAMILY=$(echo "$TASK_DEF_ARN" | cut -d '/' -f 2 | cut -d ':' -f 1)
echo "Using task family: $TASK_FAMILY" | tee -a "$LOGFILE"

# === Check if jq is installed ===
command -v jq >/dev/null 2>&1 || {
  echo "❌ 'jq' is required but not installed. Aborting." | tee -a "$LOGFILE"
  exit 1
}

# === 1. Promote the RDS Read Replica ===

echo "Promoting read replica: $REPLICA_IDENTIFIER to standalone DB..." | tee -a "$LOGFILE"

aws rds promote-read-replica \
  --db-instance-identifier "$REPLICA_IDENTIFIER" \
  --region "$REGION" >> "$LOGFILE"

echo "Waiting 120s for promotion to complete..." | tee -a "$LOGFILE"
sleep 120

# === 2. Get New RDS Endpoint ===

NEW_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$REPLICA_IDENTIFIER" \
  --region "$REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "Promoted DB endpoint: $NEW_RDS_ENDPOINT" | tee -a "$LOGFILE"

# === 3. Retrieve current DB credentials from Secrets Manager ===

echo "Fetching existing DB credentials..." | tee -a "$LOGFILE"

SECRET_STRING=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --query SecretString \
  --output text)

DB_USERNAME=$(echo "$SECRET_STRING" | jq -r '.DB_USERNAME')
DB_PASSWORD=$(echo "$SECRET_STRING" | jq -r '.DB_PASSWORD')
DB_NAME=$(echo "$SECRET_STRING" | jq -r '.DB_NAME')

# === 4. Update Secrets Manager with New RDS Endpoint ===

echo "Updating secret with new DB endpoint..." | tee -a "$LOGFILE"

UPDATED_SECRET=$(jq -n \
  --arg endpoint "$NEW_RDS_ENDPOINT" \
  --arg username "$DB_USERNAME" \
  --arg password "$DB_PASSWORD" \
  --arg dbname "$DB_NAME" \
  '{
    DB_ENDPOINT: $endpoint,
    DB_USERNAME: $username,
    DB_PASSWORD: $password,
    DB_NAME: $dbname
  }')

aws secretsmanager update-secret \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --secret-string "$UPDATED_SECRET" >> "$LOGFILE"

# === 5. Register New Task Definition ===

echo "Registering new ECS task definition..." | tee -a "$LOGFILE"

LATEST_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" \
  --region "$REGION" \
  --query "taskDefinition" --output json)

NEW_TASK_DEF=$(echo "$LATEST_TASK_DEF" | jq 'del(.status, .revision, .taskDefinitionArn, .requiresAttributes, .compatibilities)')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --region "$REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "New Task Definition ARN: $NEW_TASK_DEF_ARN" | tee -a "$LOGFILE"

# === 6. Update ECS Service to Use New Task Definition ===

echo "Updating ECS service and scaling up..." | tee -a "$LOGFILE"

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --desired-count 1 \
  --region "$REGION" >> "$LOGFILE"

echo "DR failover complete! ECS service scaled and updated." | tee -a "$LOGFILE"
