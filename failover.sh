#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
REGION="eu-central-1"
LOGFILE="failover.log"

# === Terraform Outputs ===
SECRET_ARN=$(terraform output -raw secret_arn)
REPLICA_IDENTIFIER=$(terraform output -raw read_replica_identifier)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_id)
ECS_SERVICE=$(terraform output -raw ecs_service_name)
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)

# === Start Logging ===
echo "Starting DR failover at $(date)" > "$LOGFILE"

# === Extract ECS task family name ===
TASK_FAMILY=$(echo "$TASK_DEF_ARN" | cut -d '/' -f 2 | cut -d ':' -f 1)
echo "Using ECS task family: $TASK_FAMILY" | tee -a "$LOGFILE"

# === Check jq is installed ===
command -v jq >/dev/null || {
  echo "'jq' is required but not installed." | tee -a "$LOGFILE"
  exit 1
}

# === Promote RDS Read Replica ===
echo "Checking if replica is still attached..." | tee -a "$LOGFILE"
if aws rds describe-db-instances --db-instance-identifier "$REPLICA_IDENTIFIER" --region "$REGION" >/dev/null 2>&1; then
  SOURCE_DB=$(aws rds describe-db-instances \
    --db-instance-identifier "$REPLICA_IDENTIFIER" \
    --region "$REGION" \
    --query "DBInstances[0].ReadReplicaSourceDBInstanceIdentifier" \
    --output text)

  if [[ "$SOURCE_DB" != "None" && "$SOURCE_DB" != "null" ]]; then
    echo "Promoting read replica..." | tee -a "$LOGFILE"
    aws rds promote-read-replica \
      --db-instance-identifier "$REPLICA_IDENTIFIER" \
      --region "$REGION" >> "$LOGFILE"
    echo "Waiting for promotion (120s)..." | tee -a "$LOGFILE"
    sleep 120
  else
    echo "Replica already promoted. Skipping." | tee -a "$LOGFILE"
  fi
else
  echo "Replica not found. Skipping promotion." | tee -a "$LOGFILE"
fi

# === Get new RDS endpoint ===
NEW_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$REPLICA_IDENTIFIER" \
  --region "$REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "Using DB endpoint: $NEW_RDS_ENDPOINT" | tee -a "$LOGFILE"

# === Get original credentials from JSON secret ===
echo "Retrieving DB credentials from secret..." | tee -a "$LOGFILE"
SECRET_STRING=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --query SecretString \
  --output text)

DB_USERNAME=$(echo "$SECRET_STRING" | jq -r '.DB_USERNAME')
DB_PASSWORD=$(echo "$SECRET_STRING" | jq -r '.DB_PASSWORD')
DB_NAME=$(echo "$SECRET_STRING" | jq -r '.DB_NAME')

# === Define plaintext secret names ===
DB_ENDPOINT_SECRET="lamp-db-credentials-endpoint"
DB_USERNAME_SECRET="lamp-db-credentials-username"
DB_PASSWORD_SECRET="lamp-db-credentials-password"
DB_NAME_SECRET="lamp-db-credentials-dbname"

# === Helper to create/update plain text secrets ===
put_secret() {
  local secret_name="$1"
  local value="$2"

  if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$REGION" >/dev/null 2>&1; then
    echo "Updating secret: $secret_name" | tee -a "$LOGFILE"
    aws secretsmanager put-secret-value \
      --secret-id "$secret_name" \
      --region "$REGION" \
      --secret-string "$value" >> "$LOGFILE"
  else
    echo "Creating secret: $secret_name" | tee -a "$LOGFILE"
    aws secretsmanager create-secret \
      --name "$secret_name" \
      --region "$REGION" \
      --secret-string "$value" >> "$LOGFILE"
  fi
}

# === Update ECS-compatible plain text secrets ===
put_secret "$DB_ENDPOINT_SECRET" "$NEW_RDS_ENDPOINT"
put_secret "$DB_USERNAME_SECRET" "$DB_USERNAME"
put_secret "$DB_PASSWORD_SECRET" "$DB_PASSWORD"
put_secret "$DB_NAME_SECRET"     "$DB_NAME"

# === Register updated task definition ===
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

echo "New Task Definition: $NEW_TASK_DEF_ARN" | tee -a "$LOGFILE"

# === Update ECS service and scale up ===
echo "Updating ECS service to use new task definition..." | tee -a "$LOGFILE"
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --desired-count 1 \
  --region "$REGION" >> "$LOGFILE"

echo "✅ DR failover complete! ECS service scaled and using promoted DB." | tee -a "$LOGFILE"
