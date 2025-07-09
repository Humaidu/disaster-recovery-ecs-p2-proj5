#!/bin/bash
set -euo pipefail

# RDS
# REPLICA_IDENTIFIER="lamp-dr-replica"
NEW_PRIMARY_ID="lamp-promoted-db"

# === Pull dynamic values directly from Terraform ===
echo "🔍 Fetching Terraform outputs..."

REPLICA_IDENTIFIER=$(terraform output -raw read_replica_arn | awk -F ':' '{print $6}')
REGION="eu-central-1"

# ECS
# CLUSTER_NAME="lamp-app-dr-cluster"
ECS_CLUSTER=$(terraform output -raw ecs_cluster_id)
# SERVICE_NAME="lamp-app-dr-service"
ECS_SERVICE=$(terraform output -raw ecs_service_name)
CLUSTER_NAME="$ECS_CLUSTER"
SERVICE_NAME="$ECS_SERVICE"
# TASK_FAMILY="lamp-task-family"
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
TASK_FAMILY=$(echo "$TASK_DEF_ARN" | cut -d '/' -f 2 | cut -d ':' -f 1)
CONTAINER_NAME="lamp-app"
SECRET_ARN="arn:aws:secretsmanager:${REGION}:149536482038:secret:lamp-db-credentials-YjJ3m7"

# Logging
LOGFILE="failover.log"
echo "Starting DR failover at $(date)" > $LOGFILE

# === 1. Promote the RDS Read Replica ===

echo "Promoting read replica: $REPLICA_IDENTIFIER to standalone DB..." | tee -a $LOGFILE

aws rds promote-read-replica \
  --db-instance-identifier $REPLICA_IDENTIFIER \
  --region $REGION >> $LOGFILE

echo "Waiting 120s for promotion to complete..." | tee -a $LOGFILE
sleep 120

# === 2. Get New Endpoint ===

NEW_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $REPLICA_IDENTIFIER \
  --region $REGION \
  --query "DBInstances[0].Endpoint.Address" --output text)

echo "Promoted DB endpoint: $NEW_RDS_ENDPOINT" | tee -a $LOGFILE

# === 3. Update Secrets Manager with New RDS Endpoint ===

echo "Updating secret with new DB endpoint..." | tee -a $LOGFILE

DB_PASSWORD=$(terraform output -raw db_password)

aws secretsmanager update-secret \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --secret-string "{\"DB_ENDPOINT\":\"$NEW_RDS_ENDPOINT\",\"DB_USERNAME\":\"admin\",\"DB_PASSWORD\":\"$DB_PASSWORD\",\"DB_NAME\":\"lampdb\"}" >> $LOGFILE

# === 4. Register New Task Definition with Updated Secret ===

echo "Registering updated task definition..." | tee -a $LOGFILE

# Make sure jq is available before registering new task definition
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting."; exit 1; }


LATEST_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" \
  --region "$REGION" \
  --query "taskDefinition" --output json)

NEW_TASK_DEF=$(echo $LATEST_TASK_DEF | jq 'del(.status, .revision, .taskDefinitionArn, .requiresAttributes, .compatibilities)')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --region "$REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "New Task Definition ARN: $NEW_TASK_DEF_ARN" | tee -a $LOGFILE

# === 5. Update ECS Service to Use New Task Definition ===

echo "Updating ECS service to new task definition..." | tee -a $LOGFILE

aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --desired-count 1 \
  --region "$REGION" >> $LOGFILE

echo "ECS failover complete. Service scaled to 1 with new DB." | tee -a $LOGFILE
