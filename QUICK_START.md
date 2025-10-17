# Quick Start: GitHub Actions → AWS ECR + ECS

## What You Have Already ✅

- AWS CLI configured
- ECR repository: `my-ecr-repository`
- ECS cluster: `my-ecs-cluster`
- CloudWatch log group: `/ecs/my-app`
- Dockerfile
- Task definition: `.aws/task-definition.json`
- GitHub Actions workflow: `.github/workflows/aws.yml`

## Current Status

Your GitHub Actions workflow is using **different AWS credentials** than your local setup.

### Your Local AWS Account
- Account ID: `715841325726`
- User: `github-actions-user`

### GitHub Actions AWS Account
- Unknown (check the "Check AWS Account" step in latest workflow run)

## Fix: Update GitHub Secrets

1. Go to: `https://github.com/liamyueng/learn_github_actions/settings/secrets/actions`

2. Update/Create these secrets:
   ```
   AWS_ACCESS_KEY_ID = <your-access-key-id>
   AWS_SECRET_ACCESS_KEY = <your-secret-access-key>
   AWS_REGION = us-east-2
   ```
   
   Use the credentials from your AWS IAM user (the same ones you configured locally with `aws configure`)

## Create ECS Service (Final Step)

After updating secrets and pushing successfully to ECR, create the ECS service:

```bash
# Get VPC and subnet info
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region us-east-2)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[].SubnetId" \
  --output text \
  --region us-east-2 | tr '\t' ',')

# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name my-app-sg \
  --description "My app security group" \
  --vpc-id $VPC_ID \
  --region us-east-2 \
  --query 'GroupId' \
  --output text)

# Allow HTTP traffic
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-2

# Register task definition (do this once)
aws ecs register-task-definition \
  --cli-input-json file://.aws/task-definition.json \
  --region us-east-2

# Create ECS service
aws ecs create-service \
  --cluster my-ecs-cluster \
  --service-name my-ecs-service \
  --task-definition my-ecs-task-definition \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --region us-east-2
```

## Workflow Sequence

1. ✅ **Code**: You have Dockerfile + app code
2. ✅ **ECR**: Repository created
3. ⏳ **Secrets**: Need to update GitHub secrets
4. ⏳ **Push**: `git push` triggers workflow
5. ⏳ **Build**: GitHub Actions builds Docker image
6. ⏳ **Upload**: Image pushed to ECR
7. ⏳ **Service**: Create ECS service (one-time)
8. ⏳ **Deploy**: Workflow deploys to ECS

## Troubleshooting

### Issue: "Repository does not exist"
**Cause**: GitHub secrets using wrong AWS account
**Fix**: Update GitHub secrets to match account `715841325726`

### Issue: "Service does not exist"  
**Cause**: ECS service not created
**Fix**: Run `aws ecs create-service` command above

### Issue: "Task failed to start"
**Cause**: Usually IAM role or resource limits
**Fix**: Check CloudWatch logs:
```bash
aws logs tail /ecs/my-app --follow --region us-east-2
```

## Check Everything

```bash
# Check ECR repository
aws ecr describe-repositories --region us-east-2

# Check ECS cluster
aws ecs describe-clusters --clusters my-ecs-cluster --region us-east-2

# Check ECS services
aws ecs list-services --cluster my-ecs-cluster --region us-east-2

# Check running tasks
aws ecs list-tasks --cluster my-ecs-cluster --region us-east-2
```

## Cost Alert

Running ECS Fargate 24/7:
- **0.25 vCPU + 0.5 GB RAM**: ~$10/month
- **ECR storage**: ~$0.05/month

**Stop when not needed:**
```bash
aws ecs update-service \
  --cluster my-ecs-cluster \
  --service my-ecs-service \
  --desired-count 0 \
  --region us-east-2
```

## Resources

- Full Guide: `DEPLOYMENT_GUIDE.md`
- AWS Console: https://console.aws.amazon.com/ecs/
- GitHub Actions: https://github.com/liamyueng/learn_github_actions/actions
