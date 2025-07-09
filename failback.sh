#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===

SOURCE_REGION="eu-west-1"
DR_REGION="eu-central-1"
LOGFILE="failback.log"

# DR promoted DB
DR_DB_IDENTIFIER=$(terraform output -raw read_replica_id)
NEW_REPLICA_ID="lamp-postfailback-replica"

# Secrets
SECRET_ARN=$(terraform output -raw secret_arn)

# ECS
ECS_CLUSTER=$(terraform output -raw ecs_cluster_id)
ECS_SERVICE=$(terraform output -raw ecs_service_name)
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
TASK_FAMILY=$(echo "$TASK_DEF_ARN" | cut -d '/' -f 2 | cut -d ':' -f 1)

echo "Starting DR failback at $(date)" > "$LOGFILE"

# === 1. Get Endpoint of DR DB ===
echo "Fetching endpoint of promoted DR DB..." | tee -a "$LOGFILE"

PROMOTED_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DR_DB_IDENTIFIER" \
  --region "$DR_REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

# === 2. Create New Read Replica in Primary Region ===

echo "Creating read replica in source region..." | tee -a "$LOGFILE"

aws rds create-db-instance-read-replica \
  --db-instance-identifier "$NEW_REPLICA_ID" \
  --source-db-instance-identifier "$DR_DB_IDENTIFIER" \
  --region "$SOURCE_REGION" \
  --kms-key-id "arn:aws:kms:${SOURCE_REGION}:149536482038:key/YOUR_MRK_KEY_ID" \
  --source-region "$DR_REGION" >> "$LOGFILE"

echo "Waiting 2 minutes for replica creation..." | tee -a "$LOGFILE"
sleep 120

# === 3. Update Secret in Primary Region ===

echo "Fetching existing secret values..." | tee -a "$LOGFILE"
SECRET_STRING=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$SOURCE_REGION" \
  --query SecretString --output text)

DB_USERNAME=$(echo "$SECRET_STRING" | jq -r '.DB_USERNAME')
DB_PASSWORD=$(echo "$SECRET_STRING" | jq -r '.DB_PASSWORD')
DB_NAME=$(echo "$SECRET_STRING" | jq -r '.DB_NAME')

NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$NEW_REPLICA_ID" \
  --region "$SOURCE_REGION" \
  --query "DBInstances[0].Endpoint.Address" --output text)

echo "New endpoint: $NEW_ENDPOINT" | tee -a "$LOGFILE"

echo "Updating secret in $SOURCE_REGION..." | tee -a "$LOGFILE"

UPDATED_SECRET=$(jq -n \
  --arg endpoint "$NEW_ENDPOINT" \
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
  --region "$SOURCE_REGION" \
  --secret-string "$UPDATED_SECRET" >> "$LOGFILE"

# === 4. Register Updated Task Definition in Primary ===

echo "Registering new ECS task definition in $SOURCE_REGION..." | tee -a "$LOGFILE"

LATEST_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" \
  --region "$SOURCE_REGION" \
  --query "taskDefinition" --output json)

NEW_TASK_DEF=$(echo "$LATEST_TASK_DEF" | jq 'del(.status, .revision, .taskDefinitionArn, .requiresAttributes, .compatibilities)')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --region "$SOURCE_REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "New Task Definition ARN: $NEW_TASK_DEF_ARN" | tee -a "$LOGFILE"

# === 5. Update ECS Service in Primary Region ===

echo "Updating ECS service in $SOURCE_REGION..." | tee -a "$LOGFILE"

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --desired-count 1 \
  --region "$SOURCE_REGION" >> "$LOGFILE"

echo "Failback complete. Services are now running in primary region again." | tee -a "$LOGFILE"
