#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===

REGION="eu-central-1"
LOGFILE="failover.log"

# Fetch Terraform outputs dynamically
SECRET_ARN=$(terraform output -raw secret_arn)
REPLICA_IDENTIFIER=$(terraform output -raw read_replica_identifier)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_id)
ECS_SERVICE=$(terraform output -raw ecs_service_name)
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)

# Start logging
echo "Starting DR failover at $(date)" > "$LOGFILE"

# Extract task family name from the full ARN
TASK_FAMILY=$(echo "$TASK_DEF_ARN" | cut -d '/' -f 2 | cut -d ':' -f 1)
echo "Using task family: $TASK_FAMILY" | tee -a "$LOGFILE"

# === Check dependencies ===
command -v jq >/dev/null 2>&1 || {
  echo " 'jq' is required but not installed. Aborting." | tee -a "$LOGFILE"
  exit 1
}

# === 1. Promote RDS Read Replica (if needed) ===

echo "Checking if $REPLICA_IDENTIFIER is still a read replica..." | tee -a "$LOGFILE"

if aws rds describe-db-instances \
    --db-instance-identifier "$REPLICA_IDENTIFIER" \
    --region "$REGION" > /dev/null 2>&1; then

  # Check if the instance is still a read replica
  SOURCE_DB=$(aws rds describe-db-instances \
    --db-instance-identifier "$REPLICA_IDENTIFIER" \
    --region "$REGION" \
    --query "DBInstances[0].ReadReplicaSourceDBInstanceIdentifier" \
    --output text)
  
  # Get the source DB that this instance is replicating from
  if [[ "$SOURCE_DB" != "None" && "$SOURCE_DB" != "null" ]]; then
    echo "Replica is still attached to source: $SOURCE_DB. Promoting now..." | tee -a "$LOGFILE"
    
    # Promote the read replica to a standalone DB instance
    aws rds promote-read-replica \
      --db-instance-identifier "$REPLICA_IDENTIFIER" \
      --region "$REGION" >> "$LOGFILE"

    echo "Waiting 120s for promotion to complete..." | tee -a "$LOGFILE"
    sleep 120
  else
    echo "Replica has already been promoted or has no source DB. Skipping promotion." | tee -a "$LOGFILE"
  fi
else
  echo "DB instance '$REPLICA_IDENTIFIER' does not exist. Skipping promotion." | tee -a "$LOGFILE"
fi

# Always fetch current DB endpoint (required for secrets update) 

NEW_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$REPLICA_IDENTIFIER" \
  --region "$REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "Using DB endpoint: $NEW_RDS_ENDPOINT" | tee -a "$LOGFILE"

# Retrieve current DB credentials from Secrets Manager

echo "Fetching existing DB credentials..." | tee -a "$LOGFILE"

SECRET_STRING=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --query SecretString \
  --output text)

DB_USERNAME=$(echo "$SECRET_STRING" | jq -r '.DB_USERNAME')
DB_PASSWORD=$(echo "$SECRET_STRING" | jq -r '.DB_PASSWORD')
DB_NAME=$(echo "$SECRET_STRING" | jq -r '.DB_NAME')

# Update Secrets Manager with new RDS endpoint

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

# Register updated ECS Task Definition 

echo "Registering new ECS task definition..." | tee -a "$LOGFILE"

LATEST_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" \
  --region "$REGION" \
  --query "taskDefinition" --output json)

NEW_TASK_DEF=$(echo "$LATEST_TASK_DEF" | jq 'del(
  .taskDefinitionArn,
  .revision,
  .status,
  .requiresAttributes,
  .registeredAt,
  .registeredBy,
  .compatibilities
)')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --region "$REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "New Task Definition ARN: $NEW_TASK_DEF_ARN" | tee -a "$LOGFILE"

# Update ECS service and scale up

echo "Updating ECS service to use new task definition..." | tee -a "$LOGFILE"

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --desired-count 1 \
  --region "$REGION" >> "$LOGFILE"

echo "DR failover complete! ECS service updated and scaled." | tee -a "$LOGFILE"
