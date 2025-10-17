# Complete Guide: GitHub Actions + AWS ECR + ECS Deployment

## Architecture Overview

```
┌─────────────────┐
│  GitHub Repo    │
│  (Your Code +   │
│   Dockerfile)   │
└────────┬────────┘
         │ git push
         ▼
┌─────────────────┐
│ GitHub Actions  │ ← Workflow triggered
│  - Build Image  │
│  - Run Tests    │
└────────┬────────┘
         │ docker push
         ▼
┌─────────────────┐
│   AWS ECR       │ ← Docker image stored
│ (Image Registry)│
└────────┬────────┘
         │ pull image
         ▼
┌─────────────────┐
│   AWS ECS       │ ← Containers running
│ (Run Containers)│
└─────────────────┘
```

---

## Part 1: AWS Setup

### 1.1 Create IAM User (Already Done ✅)

```bash
# Create IAM user
aws iam create-user --user-name github-actions-user

# Create access key
aws iam create-access-key --user-name github-actions-user
```

**Save the output:**
- Access Key ID: `AKIA...`
- Secret Access Key: `...`

### 1.2 Attach IAM Policies

```bash
# Attach ECR permissions
aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess

# Attach ECS permissions
aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
```

### 1.3 Create ECR Repository

```bash
# Create repository for your Docker images
aws ecr create-repository \
  --repository-name my-app \
  --region us-east-2
```

**Output:** You'll get a `repositoryUri` like:
```
123456789.dkr.ecr.us-east-2.amazonaws.com/my-app
```

### 1.4 Create ECS Cluster

```bash
# Create cluster
aws ecs create-cluster \
  --cluster-name my-cluster \
  --region us-east-2
```

### 1.5 Create Task Execution Role

```bash
# Create role for ECS tasks
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

# Attach policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

---

## Part 2: Repository Setup

### 2.1 Create Dockerfile

```dockerfile
# Example: Node.js application
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Expose port
EXPOSE 3000

# Start application
CMD ["node", "server.js"]
```

### 2.2 Create ECS Task Definition

Create `.aws/task-definition.json`:

```json
{
  "family": "my-app-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "my-app-container",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/my-app:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-app",
          "awslogs-region": "us-east-2",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

**Replace:**
- `YOUR_ACCOUNT_ID` with your AWS account ID

### 2.3 Create CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name /ecs/my-app \
  --region us-east-2
```

---

## Part 3: GitHub Setup

### 3.1 Add GitHub Secrets

Go to: `https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions`

Add these secrets:
- **AWS_ACCESS_KEY_ID**: Your IAM user access key
- **AWS_SECRET_ACCESS_KEY**: Your IAM user secret key
- **AWS_REGION**: `us-east-2` (or your preferred region)

### 3.2 Create GitHub Actions Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AWS ECS

on:
  push:
    branches: [ main ]

env:
  AWS_REGION: us-east-2
  ECR_REPOSITORY: my-app
  ECS_SERVICE: my-app-service
  ECS_CLUSTER: my-cluster
  ECS_TASK_DEFINITION: .aws/task-definition.json
  CONTAINER_NAME: my-app-container

jobs:
  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    environment: production

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2

    - name: Build, tag, and push image to Amazon ECR
      id: build-image
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

    - name: Fill in the new image ID in the Amazon ECS task definition
      id: task-def
      uses: aws-actions/amazon-ecs-render-task-definition@v1
      with:
        task-definition: ${{ env.ECS_TASK_DEFINITION }}
        container-name: ${{ env.CONTAINER_NAME }}
        image: ${{ steps.build-image.outputs.image }}

    - name: Deploy Amazon ECS task definition
      uses: aws-actions/amazon-ecs-deploy-task-definition@v1
      with:
        task-definition: ${{ steps.task-def.outputs.task-definition }}
        service: ${{ env.ECS_SERVICE }}
        cluster: ${{ env.ECS_CLUSTER }}
        wait-for-service-stability: true
```

---

## Part 4: Create ECS Service

You need a VPC with subnets and security group. Get them:

```bash
# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region us-east-2)

# Get subnets
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" \
  --output text \
  --region us-east-2)

# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name my-app-sg \
  --description "Security group for my app" \
  --vpc-id $VPC_ID \
  --region us-east-2 \
  --query 'GroupId' \
  --output text)

# Allow inbound traffic on port 3000
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr 0.0.0.0/0 \
  --region us-east-2
```

### Register Task Definition

```bash
aws ecs register-task-definition \
  --cli-input-json file://.aws/task-definition.json \
  --region us-east-2
```

### Create ECS Service

```bash
aws ecs create-service \
  --cluster my-cluster \
  --service-name my-app-service \
  --task-definition my-app-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$SUBNET_IDS],
    securityGroups=[$SG_ID],
    assignPublicIp=ENABLED
  }" \
  --region us-east-2
```

---

## Part 5: Deploy!

### Push to GitHub

```bash
git add .
git commit -m "Add deployment workflow"
git push origin main
```

### Monitor Deployment

1. **GitHub Actions**: `https://github.com/YOUR_USERNAME/YOUR_REPO/actions`
2. **AWS ECS Console**: `https://console.aws.amazon.com/ecs/`

---

## Workflow Explained

### What Happens on `git push`:

1. **Checkout**: GitHub Actions checks out your code
2. **AWS Auth**: Configures AWS credentials from secrets
3. **ECR Login**: Authenticates with AWS ECR
4. **Build**: Builds Docker image from Dockerfile
5. **Push**: Pushes image to ECR with commit SHA as tag
6. **Update Task**: Updates task definition with new image
7. **Deploy**: Deploys new task definition to ECS service
8. **Wait**: Waits for deployment to stabilize

### Expected Timeline:
- Build & Push: ~2-5 minutes
- ECS Deployment: ~2-3 minutes
- **Total: ~5-8 minutes**

---

## Troubleshooting

### Common Issues:

#### 1. "Repository does not exist in registry"
**Problem**: ECR repository not created or wrong account
```bash
# Check repository exists
aws ecr describe-repositories --region us-east-2
```

#### 2. "Service does not exist"
**Problem**: ECS service not created
```bash
# List services
aws ecs list-services --cluster my-cluster --region us-east-2
```

#### 3. "Not authorized to perform ecr:GetAuthorizationToken"
**Problem**: IAM user missing ECR permissions
```bash
# Check user policies
aws iam list-attached-user-policies --user-name github-actions-user
```

#### 4. "Task failed to start"
**Problem**: Usually resource limits or role issues
```bash
# Check ECS task logs
aws logs tail /ecs/my-app --follow --region us-east-2
```

---

## Cost Estimation

### Free Tier (First 12 months):
- **ECR**: 500 MB storage/month
- **ECS on Fargate**: No free tier
- **CloudWatch Logs**: 5 GB ingestion, 5 GB storage

### Ongoing Costs (us-east-2):
- **ECR Storage**: $0.10/GB-month
- **ECS Fargate**: 
  - 0.25 vCPU: ~$9/month (24/7)
  - 0.5 GB RAM: ~$1/month (24/7)
- **Data Transfer**: $0.09/GB (out to internet)

**Estimated Total**: ~$10-15/month for small app running 24/7

### Cost Optimization:
1. Use EC2 launch type instead of Fargate (cheaper for 24/7)
2. Stop services when not needed
3. Clean up old ECR images
4. Use lifecycle policies

---

## Best Practices

### Security:
- ✅ Use IAM roles with minimal permissions
- ✅ Store secrets in GitHub Secrets, not code
- ✅ Use OIDC instead of access keys (advanced)
- ✅ Scan images for vulnerabilities
- ✅ Use private subnets with NAT gateway (production)

### CI/CD:
- ✅ Tag images with git commit SHA
- ✅ Run tests before deployment
- ✅ Use staging environments
- ✅ Enable rollback on failure
- ✅ Monitor deployments

### Monitoring:
- ✅ Enable Container Insights
- ✅ Set up CloudWatch alarms
- ✅ Use Application Load Balancer health checks
- ✅ Implement logging

---

## Next Steps

1. ✅ Set up staging environment
2. ✅ Add automated tests to workflow
3. ✅ Configure load balancer
4. ✅ Set up auto-scaling
5. ✅ Implement blue/green deployments
6. ✅ Add monitoring and alerts

---

## Useful Commands

```bash
# View running tasks
aws ecs list-tasks --cluster my-cluster --region us-east-2

# View task details
aws ecs describe-tasks --cluster my-cluster --tasks TASK_ARN --region us-east-2

# View logs
aws logs tail /ecs/my-app --follow --region us-east-2

# Update service (force new deployment)
aws ecs update-service \
  --cluster my-cluster \
  --service my-app-service \
  --force-new-deployment \
  --region us-east-2

# Stop all tasks (emergency)
aws ecs update-service \
  --cluster my-cluster \
  --service my-app-service \
  --desired-count 0 \
  --region us-east-2
```

---

## Resources

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [AWS ECR User Guide](https://docs.aws.amazon.com/ecr/)
- [AWS ECS Developer Guide](https://docs.aws.amazon.com/ecs/)
- [Docker Documentation](https://docs.docker.com/)

---

**Created**: 2025-10-17  
**Last Updated**: 2025-10-17
