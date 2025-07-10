#!/bin/bash

# === CONFIGURATION ===

REGION="eu-central-1"

# Get dynamic values from Terraform outputs
ECS_CLUSTER=$(terraform output -raw ecs_cluster_id)
ECS_SERVICE=$(terraform output -raw ecs_service_name)
REPLICA_IDENTIFIER=$(terraform output -raw read_replica_identifier)

# Logging
LOGFILE="reset_dr.log"
echo "Resetting DR to standby mode at $(date)" > $LOGFILE

# Scale ECS service back to 0 

echo "Scaling ECS service to 0..." | tee -a $LOGFILE

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --desired-count 0 \
  --region "$REGION" >> $LOGFILE

echo "ECS DR service scaled down to 0." | tee -a $LOGFILE

# Delete the promoted RDS instance

echo "Deleting promoted RDS instance: $REPLICA_IDENTIFIER"
aws rds delete-db-instance \
  --db-instance-identifier "$REPLICA_IDENTIFIER" \
  --skip-final-snapshot \
  --region "$REGION"

echo "Waiting for DB to delete..."

echo "DR reset complete."
