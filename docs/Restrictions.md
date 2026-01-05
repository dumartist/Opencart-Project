# AWS Learner Lab - Service Restrictions

> ⚠️ **Warning:** Any attempt to exceed a service limit may result in immediate deactivation of the AWS account and all resources will be immediately deleted.

---

## 📍 Region Restrictions

| Allowed Regions | Status |
|-----------------|--------|
| **us-east-1** (N. Virginia) | ✅ Primary |
| **us-west-2** (Oregon) | ✅ Secondary |
| Other Regions | ❌ Blocked |

---

## 🖥️ EC2 Instance Restrictions

### Supported Instance Types

| Type | vCPU | Memory | Supported |
|------|------|--------|-----------|
| nano | 1 | 0.5 GB | ✅ |
| micro | 1 | 1 GB | ✅ |
| small | 1 | 2 GB | ✅ |
| medium | 2 | 4 GB | ✅ |
| large | 2 | 8 GB | ✅ |
| xlarge+ | 4+ | 16+ GB | ❌ |

### Instance Limits

| Limit | Value | Notes |
|-------|-------|-------|
| Max Concurrent Instances | **9** | Per region, excess will be terminated |
| Max vCPUs | **32** | Across all running instances |
| **CRITICAL LIMIT** | **< 20** | ≥20 instances = **IMMEDIATE ACCOUNT DELETION** |

### EBS Volume Restrictions

| Setting | Limit |
|---------|-------|
| Max Volume Size | 100 GB |
| Allowed Types | gp2, gp3, sc1, standard |
| IOPS | ❌ Not supported |

### Key Pairs

| Region | Key Pair |
|--------|----------|
| us-east-1 | `vockey` (pre-created) |
| Other regions | Must create new key pair |

### Tips

- Instances are **stopped** when session ends
- Instances are **auto-started** when new session begins
- **Stop protection** is removed at session end
- Stopped instances get **new public IP** unless using Elastic IP

---

## 🗄️ RDS Restrictions

### Supported Configurations

| Setting | Allowed Values |
|---------|----------------|
| Instance Types | nano, micro, small, medium (Burstable) |
| Database Engines | Aurora (Provisioned), Oracle, SQL Server, MySQL, PostgreSQL, MariaDB |
| Storage Size | Up to 100 GB |
| Storage Type | gp2 only |
| Instance Type | On-Demand only |

### Not Supported

| Feature | Status |
|---------|--------|
| PIOPS Storage | ❌ |
| Enhanced Monitoring | ❌ (must uncheck) |
| Reserved Instances | ❌ |

### ⚠️ Important Notes

- RDS instances may **NOT** auto-stop when session ends
- AWS **auto-starts** stopped RDS after 7 days
- **Recommendation:** Manually stop/terminate RDS to preserve budget

---

## 📁 EFS Restrictions

| Feature | Status |
|---------|--------|
| Service Access | ✅ Allowed |
| LabRole Assumption | ✅ Supported |

---

## 🔐 IAM Restrictions

### Allowed

| Action | Status |
|--------|--------|
| Use pre-created `LabRole` | ✅ |
| Use `LabInstanceProfile` | ✅ |
| Create service-linked roles | ✅ |
| Create service roles | ✅ (may need retry) |

### NOT Allowed

| Action | Status |
|--------|--------|
| Create IAM Users | ❌ |
| Create IAM Groups | ❌ |
| Create Custom IAM Roles | ❌ |

### Pre-Created Resources

```
Role: LabRole
Instance Profile: LabInstanceProfile
```

**Use Cases for LabRole:**
- Attach to EC2 instances for SSM Session Manager
- Attach to Lambda functions for AWS service access
- Attach to SageMaker notebooks for S3 access
- Use with AWS Backup for EFS backups

---

## ⚖️ Load Balancer (ELB)

| Feature | Status |
|---------|--------|
| Application Load Balancer | ✅ |
| Network Load Balancer | ✅ |
| Classic Load Balancer | ✅ |
| LabRole Assumption | ✅ |

---

## 📈 Auto Scaling

| Setting | Limit |
|---------|-------|
| Supported Instance Types | nano, micro, small, medium, large |
| Max Instances | Subject to EC2 limits (9 per region) |
| LabRole Assumption | ✅ Supported |

---

## 💾 AWS Backup

| Feature | Status |
|---------|--------|
| Service Access | ✅ Allowed |
| Backup Vaults | ✅ |
| Backup Plans | ✅ |
| Use with EFS | ✅ |

---

## 📊 CloudWatch

| Feature | Status |
|---------|--------|
| Metrics | ✅ |
| Alarms | ✅ |
| Dashboards | ✅ |
| Logs | ✅ |

---

## 📝 CloudTrail

| Feature | Status |
|---------|--------|
| Create Trail | ✅ |
| S3 Logging | ✅ |
| CloudWatch Logging | ❌ Not supported |
| LabRole Assumption | ✅ |

---

## 🪣 S3

| Feature | Status |
|---------|--------|
| Create Buckets | ✅ |
| Versioning | ✅ |
| Lifecycle Policies | ✅ |
| LabRole Assumption | ✅ |

---

## 🔔 SNS (Simple Notification Service)

| Feature | Status |
|---------|--------|
| Create Topics | ✅ |
| Email Subscriptions | ✅ |
| LabRole Assumption | ✅ |

---

## 🔐 ACM (Certificate Manager)

| Feature | Status |
|---------|--------|
| Import Certificates | ✅ |
| Request Certificates | ✅ |

---

## 🌐 VPC

| Feature | Status |
|---------|--------|
| Create VPCs | ✅ |
| Create Subnets | ✅ |
| Internet Gateways | ✅ |
| NAT Gateways | ✅ |
| Security Groups | ✅ |
| Route Tables | ✅ |

---

## 🛡️ WAF (Web Application Firewall)

| Feature | Status |
|---------|--------|
| Service Access | ✅ Allowed |

---

## 🌍 Route 53

| Feature | Status |
|---------|--------|
| Hosted Zones | ✅ |
| DNS Records | ✅ |
| Domain Registration | ❌ Not allowed |

---

## λ Lambda

| Setting | Limit |
|---------|-------|
| Max Concurrent Executions | 10 |
| LabRole Attachment | ✅ Required for AWS service access |

---

## 🔑 KMS (Key Management Service)

| Feature | Status |
|---------|--------|
| Create Keys | ✅ |
| LabRole Assumption | ✅ |

---

## 🔒 Secrets Manager

| Feature | Status |
|---------|--------|
| Create Secrets | ✅ |
| LabRole Assumption | ✅ |

---

## 📦 ElastiCache

| Feature | Status |
|---------|--------|
| Service Access | ✅ Allowed |

---

## 🐳 Container Services

### ECR (Elastic Container Registry)

| Access | Status |
|--------|--------|
| Console User | ✅ Write access |
| LabRole | Read-only |

### ECS (Elastic Container Service)

| Setting | Value |
|---------|-------|
| Instance Types | nano, micro, small, medium, large |
| Fargate | ✅ Supported |
| Task Role | Must use `LabRole` |

### EKS (Elastic Kubernetes Service)

| Setting | Value |
|---------|-------|
| Instance Types | nano, micro, small, medium, large |
| Cluster Role | `LabEksClusterRole` |

---

## 🚫 Not Supported Services

| Service | Reason |
|---------|--------|
| AWS Marketplace AMIs | ❌ Blocked |
| MacOS AMIs | ❌ Requires dedicated host |
| EC2 Fleet | ❌ Not supported |
| Reserved Instances | ❌ On-Demand only |
| Dedicated Hosts | ❌ Not available |

---

## 💰 Budget Recommendations

### To Preserve Your Lab Budget:

1. **Stop EC2 instances** before ending your session
2. **Stop/Terminate RDS** instances when not in use
3. **Delete unused resources** (EBS volumes, snapshots, etc.)
4. **Monitor CloudWatch** for running resources
5. **Use smallest instance types** that meet your needs

### Resource Lifecycle

```
Session Start → Resources auto-start (if previously stopped)
     ↓
Working Session → Resources running (budget consuming)
     ↓
Session End → EC2 instances stopped (RDS may NOT stop!)
     ↓
7 Days Idle → AWS auto-starts stopped RDS!
```

---

## 📋 Quick Reference Table

| Service | LabRole | Max Instance | Notes |
|---------|---------|--------------|-------|
| EC2 | ✅ | 9 (32 vCPU) | nano-large only |
| RDS | ✅ | - | nano-medium only, 100GB max |
| EFS | ✅ | - | Fully supported |
| ELB | ✅ | - | ALB/NLB supported |
| Auto Scaling | ✅ | 9 | Subject to EC2 limits |
| Lambda | ✅ | 10 concurrent | Attach LabRole |
| S3 | ✅ | - | Fully supported |
| CloudWatch | ✅ | - | Fully supported |
| CloudTrail | ✅ | - | No CW logging |
| AWS Backup | ✅ | - | Fully supported |
| SNS | ✅ | - | Fully supported |
| VPC | ✅ | - | Fully supported |
| IAM | ❌ | - | Use LabRole only |

---

## ⚠️ Critical Warnings

> 🚨 **ACCOUNT TERMINATION TRIGGERS:**
> - Running 20+ EC2 instances simultaneously
> - Attempting to exceed service limits
> - Using unsupported services/regions

> 💡 **Best Practice:** Always check resource count before launching new instances!

---

*Last Updated: January 2026*
