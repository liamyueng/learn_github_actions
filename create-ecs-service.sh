#!/bin/bash
# One-time setup to create ECS service
# Run this AFTER first successful image push to ECR

REGION="us-east-2"
CLUSTER="my-ecs-cluster"
SERVICE="my-ecs-service"
TASK_DEF="my-ecs-task-definition"

echo "Creating ECS service for auto-deployment..."

# Get VPC info
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION)

# Get subnets
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[].SubnetId" \
  --output text \
  --region $REGION | tr '\t' ',')

# Create/Get security group
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=my-app-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    echo "Creating security group..."
    SG_ID=$(aws ec2 create-security-group \
      --group-name my-app-sg \
      --description "Security group for my app" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)
    
    aws ec2 authorize-security-group-ingress \
      --group-id $SG_ID \
      --protocol tcp \
      --port 80 \
      --cidr 0.0.0.0/0 \
      --region $REGION
fi

echo "Security Group: $SG_ID"
echo "Subnets: $SUBNET_IDS"

# Register task definition
echo "Registering task definition..."
aws ecs register-task-definition \
  --cli-input-json file://.aws/task-definition.json \
  --region $REGION

# Create ECS service
echo "Creating ECS service..."
aws ecs create-service \
  --cluster $CLUSTER \
  --service-name $SERVICE \
  --task-definition $TASK_DEF \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --region $REGION

echo ""
echo "✅ ECS service created!"
echo ""
echo "Now every 'git push' will automatically deploy to AWS! 🚀"
echo ""
echo "To see your running tasks:"
echo "aws ecs list-tasks --cluster $CLUSTER --region $REGION"
