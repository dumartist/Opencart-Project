# Project Notes: Issues, Challenges & Solutions

> 📝 **Document Purpose:** This document records all major issues encountered during the OpenCart AWS deployment project, focusing on AWS Learner Lab restrictions and the solutions or alternatives we implemented.

---

## Table of Contents

1. [SSH Key Authentication Issues](#1-ssh-key-authentication-issues)
2. [AWS Backup Lifecycle Restrictions](#2-aws-backup-lifecycle-restrictions)
3. [IAM Restrictions - No Custom Roles](#3-iam-restrictions---no-custom-roles)
4. [ElastiCache/Redis - Gave Up](#4-elasticacheredis---gave-up)
5. [EFS Access Architecture](#5-efs-access-architecture)
6. [RDS Bastion Access Debate](#6-rds-bastion-access-debate)
7. [Instance Type & Count Limits](#7-instance-type--count-limits)
8. [Region Restrictions](#8-region-restrictions)
9. [Sensitive Variables Security](#9-sensitive-variables-security)
10. [Cloudflare Free Tier Limitations](#10-cloudflare-free-tier-limitations)

---

## 1. SSH Key Authentication Issues

### ❌ Problem
After deploying infrastructure, couldn't SSH from bastion to web servers:
```bash
ubuntu@bastion:~$ ssh ubuntu@10.0.101.18
Permission denied (publickey).
```

### 🔍 Root Cause
SSH key authentication requires:
- **Public key** → on the server (web servers had this via `aws_key_pair`)
- **Private key** → on the client (bastion did NOT have this!)

The bastion only had the public key registered. When SSHing to web servers, it had no private key to authenticate with.

### ✅ Solution
Auto-generate SSH key pair in Terraform and inject private key into bastion:

```hcl
# Generate SSH key pair using Terraform
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "bastion-key"
  public_key = tls_private_key.bastion.public_key_openssh
}

# Bastion user_data installs private key
resource "aws_instance" "bastion" {
  user_data = <<-EOF
    # ... other setup ...
    
    # Install private key for SSH access to web servers
    mkdir -p /home/ubuntu/.ssh
    cat > /home/ubuntu/.ssh/id_rsa << 'KEYEOF'
${tls_private_key.bastion.private_key_pem}
KEYEOF
    chmod 600 /home/ubuntu/.ssh/id_rsa
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh
  EOF
}
```

### 📊 Flow Diagram
```
┌──────────────────────────────────────────────────────────────────┐
│                    SSH KEY AUTHENTICATION                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  tls_private_key                                                 │
│       │                                                          │
│       ├──► Public Key ──► aws_key_pair ──► Web Servers           │
│       │                                                          │
│       └──► Private Key ──► Bastion user_data                     │
│                                │                                 │
│                                ▼                                 │
│                    /home/ubuntu/.ssh/id_rsa                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. AWS Backup Lifecycle Restrictions

### ❌ Problem
Terraform apply failed with error:
```
Error: creating Backup Plan: InvalidParameterValueException: 
DeleteAfterDays cannot be less than 90 days apart from MoveToColdStorageAfterDays
```

### 🔍 Root Cause
AWS Backup has a **minimum 90-day gap requirement** between moving to cold storage and deletion. Our original config:
```hcl
lifecycle {
  cold_storage_after = 7    # Move to cold after 7 days
  delete_after       = 30   # Delete after 30 days
  # Gap = 23 days ❌ (must be ≥90)
}
```

### ✅ Solution
For short-term backups (daily), removed cold storage entirely:

```hcl
# Daily backup - no cold storage (short retention)
rule {
  rule_name = "daily-efs-backup"
  lifecycle {
    delete_after = 30  # Just delete, no cold storage
  }
}

# Weekly backup - longer retention, still no cold storage
rule {
  rule_name = "weekly-efs-backup"
  lifecycle {
    delete_after = 90
  }
}
```

### 💡 Lesson Learned
Cold storage only makes sense for **long-term archival** (≥90 days retention). For disaster recovery with shorter retention, just use standard storage.

---

## 3. IAM Restrictions - No Custom Roles

### ❌ Problem
AWS Learner Lab does NOT allow:
- Creating IAM Users
- Creating IAM Groups
- Creating Custom IAM Roles

Attempting to create custom roles results in:
```
AccessDenied: User is not authorized to perform: iam:CreateRole
```

### ✅ Solution
Use pre-existing Learner Lab resources:

| Resource | Pre-created Name | Usage |
|----------|------------------|-------|
| IAM Role | `LabRole` | EC2, Lambda, Backup, etc. |
| Instance Profile | `LabInstanceProfile` | EC2 instances |

```hcl
# Use existing instance profile
data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

# Use LabRole for AWS Backup
resource "aws_backup_selection" "efs" {
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  # ...
}
```

### ⚠️ Limitation
Cannot create fine-grained IAM policies. All services share the same `LabRole` with broad permissions.

---

## 4. ElastiCache/Redis - Gave Up

### ❌ Problem
Initially considered Redis for:
- Session management across ASG instances
- Database query caching
- Shopping cart persistence

### 🔍 Challenges
1. **Cost**: ElastiCache adds monthly charges
2. **Complexity**: Additional infrastructure to manage
3. **Learner Lab**: Limited budget/credits

### ✅ Alternative Solution
Used **Cloudflare CDN + ALB Sticky Sessions** instead:

```hcl
# ALB Sticky Sessions
resource "aws_lb_target_group" "main" {
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = true
  }
}
```

**How it works:**
- User's first request → routed to any web server
- ALB sets a cookie → "sticks" user to that server
- All subsequent requests → same server (24 hours)
- PHP sessions stored locally (file-based)

### 📊 Comparison

| Aspect | Redis | Sticky Sessions |
|--------|-------|-----------------|
| Cost | 💰 Higher | ✅ Free |
| Complexity | Complex | Simple |
| Session Survival | ✅ Survives instance death | ❌ Lost if instance dies |
| Best For | High traffic, critical sessions | Learning, small-medium sites |

### 💡 Verdict
**Gave up on Redis** - Sticky sessions sufficient for learning environment and small e-commerce.

---

## 5. EFS Access Architecture

### ❓ Question
"How do I mount EFS from bastion for debugging?"

### 🔍 Discovery
EFS security group only allows access from **web servers**:

```hcl
resource "aws_security_group" "efs" {
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]  # Web only!
  }
}
```

### ✅ Correct Architecture (Not a Bug!)

```
┌─────────────────────────────────────────────────────────────┐
│                    DATA ACCESS LAYERS                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   BASTION ──SSH──► WEB SERVERS ──NFS──► EFS                 │
│   (Jump)           (App Layer)          (Data)              │
│                                                             │
│   ✅ This is CORRECT security design!                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 💡 How to Access EFS (Correct Way)

```bash
# 1. SSH to bastion
ssh -i bastion-key ubuntu@<bastion-ip>

# 2. SSH to web server
ssh ubuntu@10.0.101.18

# 3. EFS already mounted!
ls -la /var/www/html/opencart
```

### 🔐 Security Benefit
Even if attacker compromises bastion, they cannot directly access application files on EFS.

---

## 6. RDS Bastion Access Debate

### ❓ Question
"Should bastion have direct RDS access?"

### 📊 Current Configuration
```hcl
resource "aws_security_group" "rds" {
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [
      aws_security_group.web.id,
      aws_security_group.bastion.id  # ← Allowed!
    ]
  }
}
```

### 🤔 Two Schools of Thought

| Strict Security | Practical Approach |
|-----------------|-------------------|
| Bastion → Web → RDS only | Bastion → RDS direct |
| More secure | DBA convenience |
| Less convenient | Common in real-world |

### ✅ Decision: Kept Practical Approach

**Reasons:**
1. DBAs need quick access for troubleshooting
2. Running migrations/scripts
3. Common industry practice
4. Learning environment (not ultra-sensitive data)

**Strict alternative (if needed):**
```hcl
# Remove bastion from RDS security group
security_groups = [aws_security_group.web.id]  # Web only
```

---

## 7. Instance Type & Count Limits

### ❌ AWS Learner Lab Restrictions

| Limit | Value | Consequence |
|-------|-------|-------------|
| Instance Types | nano → large only | No xlarge+ |
| Max Instances | 9 per region | Plan ASG carefully |
| Max vCPUs | 32 total | Limits scaling |
| **CRITICAL** | < 20 instances | ≥20 = Account deletion! |

### ✅ Our Configuration

```hcl
resource "aws_autoscaling_group" "main" {
  min_size         = 2    # Minimum 2 for HA
  max_size         = 3    # Max 3 (safe within limits)
  desired_capacity = 2
}

# Instances used:
# - 2-3 Web servers (ASG)
# - 1 Bastion
# Total: 3-4 instances (well within limit)
```

### 💡 Lesson
Always plan instance count carefully. Account deletion is **instant and irreversible**.

---

## 8. Region Restrictions

### ❌ Allowed Regions Only

| Region | Status |
|--------|--------|
| us-east-1 (N. Virginia) | ✅ Primary |
| us-west-2 (Oregon) | ✅ Secondary |
| All others | ❌ Blocked |

### ✅ Configuration

```hcl
# provider.tf
provider "aws" {
  region = "us-east-1"  # Must use allowed region
}
```

### ⚠️ Impact
- No multi-region disaster recovery
- Limited geographic distribution
- All resources must be in us-east-1 or us-west-2

---

## 9. Sensitive Variables Security

### ❌ Original Problem
Hardcoded credentials in `main.tf`:
```hcl
# BAD - exposed in version control!
locals {
  db_password = "MySecretPassword123!"
}
```

### ✅ Solution: Variable Separation

**Created three files:**

1. **variables.tf** - Declarations (safe to commit)
```hcl
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
```

2. **terraform.tfvars** - Actual values (in .gitignore!)
```hcl
db_password = "ActualSecretPassword123!"
```

3. **terraform.tfvars.example** - Template for others
```hcl
db_password = "CHANGE_ME_strong_password_here"
```

### 📁 .gitignore
```
terraform.tfvars
*.tfstate
*.tfstate.backup
bastion-key
*.pem
```

---

## 10. Cloudflare Free Tier Limitations

### 🆓 What We Got (Free)

| Feature | Status | Benefit |
|---------|--------|---------|
| SSL/TLS (Full) | ✅ | HTTPS encryption |
| DDoS Protection | ✅ | Always on |
| Bot Fight Mode | ✅ | Basic bot blocking |
| HTTP/2 + HTTP/3 | ✅ | Performance |
| CDN Caching | ✅ | Edge caching |
| 3 Page Rules | ✅ | Custom caching |

### ❌ What We Couldn't Use (Paid Only)

| Feature | Tier Required |
|---------|---------------|
| WAF (Custom Rules) | Pro ($20/mo) |
| Advanced Bot Management | Enterprise |
| Load Balancing | Pro |
| Image Optimization (Polish) | Pro |
| Rate Limiting (Advanced) | Pro |

### ✅ Our Configuration

```
Page Rules (3 max on free):
1. /image/* → Cache 1 month (product images)
2. /catalog/view/* → Cache 7 days (CSS/JS)
3. /admin/* → Bypass cache (admin panel)
```

### 💡 Workaround for WAF
Used free Bot Fight Mode + Browser Integrity Check instead of paid WAF rules.

---

## Summary: Key Restrictions & Solutions

| Challenge | Restriction | Solution |
|-----------|-------------|----------|
| SSH to web servers | Private key missing | Auto-generate in Terraform |
| AWS Backup lifecycle | 90-day cold storage gap | Remove cold storage for short retention |
| Custom IAM roles | Not allowed | Use LabRole/LabInstanceProfile |
| Redis/ElastiCache | Cost/complexity | ALB sticky sessions |
| EFS from bastion | By design (security) | SSH via web servers |
| Instance limits | Max 9, 32 vCPU | Plan ASG carefully |
| Regions | us-east-1/us-west-2 only | Deploy in us-east-1 |
| WAF | Paid feature | Free Bot Fight Mode |

---

## Lessons Learned

1. **Read restrictions first** - Before designing, know the limits
2. **Use pre-existing resources** - LabRole exists for a reason
3. **Simple > Complex** - Sticky sessions work fine for learning
4. **Security by layers** - Bastion → Web → Data is correct
5. **Protect secrets** - terraform.tfvars + .gitignore
6. **Test SSH early** - Key issues waste hours
7. **Plan instance count** - Account deletion is final!

---

*Last Updated: January 5, 2026*
