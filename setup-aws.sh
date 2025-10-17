#!/bin/bash
# Quick setup script for AWS ECS deployment
# Run this after configuring AWS CLI

set -e  # Exit on error

REGION="us-east-2"
CLUSTER_NAME="my-ecs-cluster"
REPOSITORY_NAME="my-ecr-repository"
SERVICE_NAME="my-ecs-service"
TASK_FAMILY="my-ecs-task-definition"
CONTAINER_NAME="my-container-name"

echo "🚀 Setting up AWS resources for ECS deployment..."

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ Using AWS Account: $ACCOUNT_ID"

# Check if ECR repository exists
echo "📦 Checking ECR repository..."
if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $REGION 2>/dev/null; then
    echo "✅ ECR repository '$REPOSITORY_NAME' already exists"
else
    echo "Creating ECR repository..."
    aws ecr create-repository --repository-name $REPOSITORY_NAME --region $REGION
    echo "✅ ECR repository created"
fi

# Check if ECS cluster exists
echo "🔧 Checking ECS cluster..."
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "✅ ECS cluster '$CLUSTER_NAME' already exists"
else
    echo "Creating ECS cluster..."
    aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $REGION
    echo "✅ ECS cluster created"
fi

# Check if CloudWatch log group exists
echo "📊 Checking CloudWatch log group..."
if aws logs describe-log-groups --log-group-name-prefix "/ecs/my-app" --region $REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "/ecs/my-app"; then
    echo "✅ CloudWatch log group already exists"
else
    echo "Creating CloudWatch log group..."
    aws logs create-log-group --log-group-name /ecs/my-app --region $REGION
    echo "✅ CloudWatch log group created"
fi

# Check if ecsTaskExecutionRole exists
echo "🔐 Checking IAM role..."
if aws iam get-role --role-name ecsTaskExecutionRole 2>/dev/null; then
    echo "✅ ecsTaskExecutionRole already exists"
else
    echo "Creating ecsTaskExecutionRole..."
    aws iam create-role \
      --role-name ecsTaskExecutionRole \
      --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Principal": {"Service": "ecs-tasks.amazonaws.com"},
          "Action": "sts:AssumeRole"
        }]
      }'
    
    aws iam attach-role-policy \
      --role-name ecsTaskExecutionRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    echo "✅ ecsTaskExecutionRole created"
fi

# Get default VPC and subnets for ECS service creation
echo "🌐 Getting VPC information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text --region $REGION | tr '\t' ',')

echo "✅ VPC ID: $VPC_ID"
echo "✅ Subnet IDs: $SUBNET_IDS"

# Create security group if it doesn't exist
echo "🔒 Checking security group..."
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
    
    # Allow inbound on port 80
    aws ec2 authorize-security-group-ingress \
      --group-id $SG_ID \
      --protocol tcp \
      --port 80 \
      --cidr 0.0.0.0/0 \
      --region $REGION
    
    echo "✅ Security group created: $SG_ID"
else
    echo "✅ Security group already exists: $SG_ID"
fi

echo ""
echo "=" echo "🎉 AWS Setup Complete!"
echo "=="
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Update GitHub Secrets with these values:"
echo "   AWS_ACCESS_KEY_ID: (your access key)"
echo "   AWS_SECRET_ACCESS_KEY: (your secret key)"
echo "   AWS_REGION: $REGION"
echo ""
echo "2. Update .aws/task-definition.json with:"
echo "   - Account ID: $ACCOUNT_ID"
echo "   - Image: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME:latest"
echo ""
echo "3. Create ECS service (after first successful image push):"
echo "   aws ecs create-service \\"
echo "     --cluster $CLUSTER_NAME \\"
echo "     --service-name $SERVICE_NAME \\"
echo "     --task-definition $TASK_FAMILY \\"
echo "     --desired-count 1 \\"
echo "     --launch-type FARGATE \\"
echo "     --network-configuration \"awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}\" \\"
echo "     --region $REGION"
echo ""
echo "4. Push to GitHub to trigger deployment!"
echo ""
