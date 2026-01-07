# OpenCart Terraform Architecture Documentation

## Overview

This document explains how the OpenCart 3.0.5.0 Terraform deployment works. The architecture provides a production-style, auto-scaled e-commerce platform on AWS, adapted for AWS Learner Lab constraints.

---

## Architecture Diagram

```
                                    ┌─────────────────┐
                                    │      User       │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │  Cloudflare CDN │  (External - DNS & Caching)
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │ Internet Gateway│
                                    └────────┬────────┘
                                             │
┌────────────────────────────────────────────┼─────────────────────────────────────────────┐
│                                   VPC (10.0.0.0/16)                                      │
│                                            │                                             │
│  ┌─────────────────────────────────────────┼──────────────────────────────────────────┐  │
│  │                              PUBLIC SUBNETS                                        │  │
│  │  ┌──────────────────┐       ┌───────────▼───────────┐       ┌──────────────────┐   │  │
│  │  │ Public Subnet 1  │       │  Application Load     │       │ Public Subnet 2  │   │  │
│  │  │  10.0.1.0/24     │◄─────►│  Balancer (ALB)       │◄─────►│  10.0.2.0/24     │   │  │
│  │  │  (AZ-1)          │       │masquerade-opencart-alb│       │  (AZ-2)          │   │  │
│  │  └────────┬─────────┘       └───────────┬───────────┘       └──────────────────┘   │  │
│  │           │                             │                                          │  │
│  │  ┌────────▼─────────┐                   │                                          │  │
│  │  │  Bastion Host    │                   │                                          │  │
│  │  │  (t2.micro)      │                   │                                          │  │
│  │  │  + SSM Agent     │                   │                                          │  │
│  │  └──────────────────┘                   │                                          │  │
│  │           │                    ┌────────▼────────┐                                 │  │
│  │           │                    │   NAT Gateway   │                                 │  │
│  │           │                    └────────┬────────┘                                 │  │
│  └───────────┼─────────────────────────────┼──────────────────────────────────────────┘  │
│              │                             │                                             │
│  ┌───────────┼─────────────────────────────┼──────────────────────────────────────────┐  │
│  │           │              PRIVATE SUBNETS│                                          │  │
│  │  ┌────────▼─────────┐          ┌────────▼────────┐       ┌──────────────────┐      │  │
│  │  │ Private Subnet 1 │          │  Auto Scaling   │       │ Private Subnet 2 │      │  │
│  │  │  10.0.101.0/24   │◄────────►│     Group       │◄─────►│  10.0.102.0/24   │      │  │
│  │  │  (AZ-1)          │          │   (2-3 nodes)   │       │  (AZ-2)          │      │  │
│  │  │                  │          │   + SSM Agent   │       │                  │      │  │
│  │  └────────┬─────────┘          └────────┬────────┘       └────────┬─────────┘      │  │
│  │           │                             │                         │                │  │
│  │           │     ┌───────────────────────┼─────────────────────────┘                │  │
│  │           │     │                       │                                          │  │
│  │  ┌────────▼─────▼───┐          ┌────────▼────────┐                                 │  │
│  │  │       EFS        │          │   RDS MySQL     │                                 │  │
│  │  │ (OpenCart Files) │          │   (Multi-AZ)    │                                 │  │
│  │  │ /var/www/html/   │          │   db.t3.micro   │                                 │  │
│  │  │    opencart      │          └─────────────────┘                                 │  │
│  │  └──────────────────┘                                                              │  │
│  └────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              MONITORING                                            │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                              │  │
│  │  │  CloudWatch  │  │  CloudTrail  │  │  SNS Topic   │                              │  │
│  │  │  Dashboard   │  │  (Audit)     │  │  (Alerts)    │                              │  │
│  │  └──────────────┘  └──────────────┘  └──────┬───────┘                              │  │
│  │                                             │                                      │  │
│  │                                    ┌────────▼────────┐                             │  │
│  │                                    │ Email Alerts    │                             │  │
│  │                                    └─────────────────┘                             │  │
│  └────────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### 1. Data Sources

```hcl
# Existing Learner Lab instance profile (no IAM creation allowed)
data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

# Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Available Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}
```

**Purpose**: 
- Fetches the pre-existing LabInstanceProfile (Learner Lab constraint)
- Gets the latest Ubuntu 22.04 AMI dynamically
- Discovers available AZs for multi-AZ deployment

---

### 2. Local Variables

```hcl
# Sensitive credentials defined as Terraform variables
variable "db_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}

variable "opencart_admin_password" {
  description = "OpenCart admin panel password"
  type        = string
  sensitive   = true
}

locals {
  project_name = "masquerade-opencart"
  environment  = "production"

  # Network
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

  # Database credentials (from variables - never hardcode!)
  db_name     = var.db_name        # default: "opencartdb"
  db_username = var.db_username    # default: "ocadmin"
  db_password = var.db_password    # from terraform.tfvars
  db_port     = 3306

  # OpenCart Admin (from variables)
  admin_username = var.opencart_admin_username
  admin_password = var.opencart_admin_password
  admin_email    = var.opencart_admin_email

  # EC2
  key_name         = "bastion-key"
  opencart_version = "3.0.5.0"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    Application = "OpenCart"
  }
}
```

> 📝 **See [NOTE.md](NOTE.md) for all configurable variables and their defaults.**

---

### 3. Networking (VPC)

| Resource | CIDR/Config | Purpose |
|----------|-------------|---------|
| VPC | 10.0.0.0/16 | Main network container |
| Public Subnet 1 | 10.0.1.0/24 | ALB, Bastion, NAT Gateway |
| Public Subnet 2 | 10.0.2.0/24 | ALB redundancy |
| Private Subnet 1 | 10.0.101.0/24 | Web servers, RDS, EFS |
| Private Subnet 2 | 10.0.102.0/24 | Multi-AZ redundancy |
| Internet Gateway | - | Public internet access |
| NAT Gateway | - | Outbound internet for private subnets |
| Elastic IP | - | Static IP for NAT Gateway |

**Key Difference from Moodle**: OpenCart includes a NAT Gateway so private subnet instances can download packages and OpenCart from GitHub.

---

### 4. Security Groups

| Security Group | Inbound Rules | Purpose |
|----------------|---------------|---------|
| `bastion-sg` | 22 from 0.0.0.0/0 | SSH access to bastion |
| `alb-sg` | 443 from Cloudflare IPs only | **Blocks direct ALB access** |
| `web-sg` | 80 from ALB, 22 from Bastion | Web server access |
| `efs-sg` | 2049 from Web | NFS mount from web servers |
| `rds-sg` | 3306 from Web + Bastion | MySQL access |

> [!IMPORTANT]
> **ALB Security Hardening**: The ALB security group only allows HTTPS (port 443) from [Cloudflare IP ranges](https://cloudflare.com/ips-v4). This prevents attackers from bypassing Cloudflare's DDoS protection by accessing the ALB directly. The HTTP listener redirects to HTTPS (301 redirect).

**Security Chain**:
```
Internet → Cloudflare CDN (HTTPS) → ALB (Cloudflare IPs only) → Web Servers → EFS/RDS
                                                                      ↑
                                                              Bastion (SSH)
```

---

### 5. EFS (Elastic File System)

```hcl
resource "aws_efs_file_system" "opencart" {
  creation_token   = "${local.project_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  # Cost optimization: Move infrequently accessed files to cheaper storage
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"  # Move to IA after 30 days
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"  # Move back when accessed
  }
}

resource "aws_efs_mount_target" "opencart" {
  count           = length(aws_subnet.private)
  file_system_id  = aws_efs_file_system.opencart.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}
```

**Purpose**: 
- Shared storage for OpenCart files across all ASG instances
- Mounted at `/var/www/html/opencart`
- Contains: OpenCart code, images, uploads, cache
- Encrypted at rest

**Lifecycle Policy (Cost Optimization)**:
- Files not accessed for 30 days → moved to Infrequent Access (IA) storage
- IA storage costs ~87% less than standard storage
- Files automatically move back to standard when accessed

---

### 5.1 EFS Backup (AWS Backup)

```hcl
# Backup Vault
resource "aws_backup_vault" "opencart" {
  name = "${local.project_name}-backup-vault"
}

# Backup Plan
resource "aws_backup_plan" "efs" {
  name = "${local.project_name}-efs-backup-plan"

  # Daily backup
  rule {
    rule_name         = "daily-efs-backup"
    target_vault_name = aws_backup_vault.opencart.name
    schedule          = "cron(0 5 * * ? *)"  # 5 AM UTC

    lifecycle {
      cold_storage_after = 7   # Move to cold storage after 7 days
      delete_after       = 30  # Delete after 30 days
    }
  }

  # Weekly backup (longer retention)
  rule {
    rule_name         = "weekly-efs-backup"
    target_vault_name = aws_backup_vault.opencart.name
    schedule          = "cron(0 6 ? * SUN *)"  # Sunday 6 AM UTC

    lifecycle {
      delete_after = 90  # Keep for 90 days
    }
  }
}

# Backup Selection (uses LabRole for Learner Lab compatibility)
resource "aws_backup_selection" "efs" {
  name         = "${local.project_name}-efs-backup-selection"
  plan_id      = aws_backup_plan.efs.id
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  resources = [aws_efs_file_system.opencart.arn]
}
```

**Backup Strategy**:
| Schedule | Retention | Cold Storage | Purpose |
|----------|-----------|--------------|---------|
| Daily (5 AM UTC) | 30 days | After 7 days | Regular recovery points |
| Weekly (Sunday 6 AM) | 90 days | No | Long-term recovery |

**Recovery Time**:
- RTO: ~30 minutes (restore from backup)
- RPO: 24 hours (daily backup interval)

---

### 6. RDS (MySQL Database)

```hcl
resource "aws_db_instance" "opencart" {
  identifier        = "${local.project_name}-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_encrypted = true

  db_name  = local.db_name      # from variable
  username = local.db_username  # from variable
  password = local.db_password  # from variable (sensitive)
  port     = local.db_port      # 3306

  multi_az = true

  # DISASTER RECOVERY
  backup_retention_period   = 7                    # Keep 7 days of automated backups
  backup_window             = "03:00-04:00"        # Daily backup at 3 AM UTC
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.project_name}-final-snapshot"
}
```

**Features**:
- Multi-AZ for high availability (automatic failover in ~2 minutes)
- MySQL 8.0 (OpenCart compatible)
- Encrypted storage
- Private subnet only (not publicly accessible)

**Disaster Recovery**:
- 7-day automated backup retention
- Daily backups at 3 AM UTC
- Final snapshot created before deletion (prevents data loss)
- Point-in-time recovery available within retention period

---

### 7. Caching & Session Management (Cloudflare CDN + ALB Sticky Sessions)

Instead of using ElastiCache Redis (which adds cost and complexity), this architecture uses:

**Cloudflare CDN (External)**:
- Static asset caching (images, CSS, JS)
- DDoS protection
- SSL/TLS termination (Full mode)
- Global edge network for faster delivery
- Bot protection (Bot Fight Mode)
- HTTP/2 & HTTP/3 (QUIC) protocol optimization

#### Cloudflare Configuration Details

**Speed Optimizations (Enabled):**
| Feature | Purpose |
|---------|--------|
| HTTP/2 | Multiplexed connections, faster loading |
| HTTP/3 (QUIC) | UDP-based, reduced latency |
| HTTP/2 to Origin | HTTP/2 between Cloudflare and ALB |
| 0-RTT Connection Resumption | Faster repeat connections |
| Early Hints | Preload assets before page loads |
| Speed Brain | AI-powered optimization |
| TLS 1.3 | Faster, more secure TLS handshake |

**Security Settings:**
| Feature | Setting |
|---------|--------|
| Security Level | Medium |
| Bot Fight Mode | Enabled |
| Browser Integrity Check | Enabled |
| DDoS Protection | Always On |

**Network Settings:**
| Feature | Setting | Purpose |
|---------|---------|--------|
| IPv6 Compatibility | Enabled | Support IPv6 clients |
| Pseudo IPv4 | Add Header | IPv6→IPv4 compatibility for origin |
| WebSockets | Enabled | Real-time features support |
| IP Geolocation | Enabled | CF-IPCountry header |
| Onion Routing | Enabled | Tor network support |
| Max Upload Size | 100 MB | Product image uploads |

**Page Rules (Caching Strategy):**
```
Rule 1: shop.dumartist.my.id/image/*
  → Cache Everything, Edge TTL: 1 month, Browser TTL: 1 year
  → Product images cached aggressively

Rule 2: shop.dumartist.my.id/catalog/view/*  
  → Cache Everything, Edge TTL: 7 days, Browser TTL: 1 month
  → Theme CSS/JS cached with moderate refresh

Rule 3: shop.dumartist.my.id/admin/*
  → Cache Level: Bypass
  → Admin panel never cached (dynamic content)
```

**ALB Sticky Sessions**:
```hcl
resource "aws_lb_target_group" "main" {
  # ... other config
  
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = true
  }
}
```

**How It Works**:
- User's first request is routed to any available web server
- ALB sets a cookie that "sticks" the user to that server
- All subsequent requests go to the same server for 24 hours
- PHP sessions are stored locally on the server (file-based)
- EFS ensures uploaded files are shared across all instances

**Trade-offs**:
| Aspect | With Redis | With Sticky Sessions |
|--------|-----------|---------------------|
| Cost | Higher (ElastiCache charges) | Lower (no extra service) |
| Complexity | More components | Simpler architecture |
| Session Persistence | Survives instance termination | Lost if instance terminates |
| Scaling | Seamless | May need session re-login |

**Best For**: Learning environments, small-medium traffic sites, cost-sensitive deployments.

---

### 8. Bastion Host

```hcl
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  key_name               = local.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y mysql-client
  EOF
}
```

**Purpose**: 
- Jump host for SSH access to private instances
- MySQL client for database administration
- Located in public subnet with public IP

---

### 9. Application Load Balancer

```hcl
resource "aws_lb" "main" {
  name               = "${local.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "main" {
  health_check {
    path                = "/health.php"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = true
  }
}
```

**Key Features**:
- Health check on `/health.php` (created immediately by user data)
- Sticky sessions for consistent shopping cart experience
- 24-hour cookie duration

---

### 10. Launch Template & User Data (The Core Automation)

This is where the OpenCart installation magic happens. Let's break it down:

#### Variable Handling

```hcl
locals {
  user_data_opencart = <<-EOT
    # Terraform-interpolated variables (resolved at plan time)
    EFS_ID="${aws_efs_file_system.opencart.id}"
    DB_HOST="${aws_db_instance.opencart.address}"
    ALB_DNS="${aws_lb.main.dns_name}"
    
    # Shell variables (escaped with $$, resolved at runtime)
    WEB_ROOT="/var/www/html/opencart"
    PHP_VERSION="8.1"
  EOT
}
```

**Critical Escaping Rules**:
| Syntax | What It Becomes | When Evaluated |
|--------|-----------------|----------------|
| `${aws_...}` | Actual AWS resource value | Terraform plan |
| `$${VAR}` | `${VAR}` (shell variable) | EC2 runtime |
| `$VAR` or `$1` | Shell variable | EC2 runtime |

---

#### User Data Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           EC2 Instance Boot                              │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 0: Install SSM Agent for Session Manager access                     │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 1: Create health.php immediately                                    │
│         → ALB sees instance as healthy                                   │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 2: Update system packages (with retries)                            │
│         apt-get update && install base packages                          │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 3: Add PHP PPA and install PHP 8.1                                  │
│         php8.1, php8.1-mysql, php8.1-gd, php8.1-curl, etc.               │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 4: Configure PHP                                                    │
│         - memory_limit = 512M                                            │
│         - session.save_handler = files (local)                           │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 5: Configure Apache                                                 │
│         - Enable rewrite, headers modules                                │
│         - DocumentRoot = /var/www/html/opencart                          │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 6: Wait for RDS (30 retries × 10s = 5 minutes max)                  │
│         mysqladmin ping -h DB_HOST                                       │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 7: Mount EFS (30 retries with DNS/connectivity checks)              │
│         mount -t nfs4 EFS_DNS:/ /var/www/html/opencart                   │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 8: Acquire flock (prevents race condition)                          │
│         Only ONE instance performs installation                          │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 9: Install OpenCart (if not already on EFS)                         │
│          - Download from GitHub                                          │
│          - Extract to EFS                                                │
│          - Generate config.php with DB settings                          │
│          - Set permissions                                               │
│          - Remove /install directory                                     │
├──────────────────────────────────────────────────────────────────────────┤
│ Step 10: Restart Apache                                                  │
│          OpenCart is now live!                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

#### Key Code Sections

**1. Immediate Health Check**
```bash
mkdir -p "$${WEB_ROOT}" /var/www/html /var/lock
cat > /var/www/html/health.php << 'HEALTHCHECK'
<?php http_response_code(200); echo "OK"; ?>
HEALTHCHECK
```

**2. Retry Loops**
```bash
for i in {1..5}; do
  apt-get update -y && apt-get upgrade -y && break
  log_step "Update attempt $i failed, retrying in 10s..."
  sleep 10
done || { log_step "ERROR: Failed after 5 attempts"; exit 1; }
```

**3. PHP Session Configuration (File-based with Sticky Sessions)**
```bash
# Sessions are stored locally on each server
# ALB sticky sessions ensure user stays on same server
mkdir -p /var/lib/php/sessions
chown www-data:www-data /var/lib/php/sessions
```

**4. Bootstrap Lock (Race Prevention)**
```bash
(
  flock -x -w 600 200 || { log_step "ERROR: Failed to acquire lock"; exit 1; }
  
  if [ -f "$${WEB_ROOT}/index.php" ]; then
    log_step "OpenCart already installed on EFS. Skipping."
  else
    # First instance performs installation
    wget "https://github.com/opencart/opencart/releases/download/..."
    unzip opencart.zip
    # ... rest of installation
  fi
) 200>"$${LOCK_FILE}"
```

**5. OpenCart config.php Generation**
```bash
cat > "$${WEB_ROOT}/config.php" << CONFIG
<?php
define('HTTP_SERVER', 'http://$${ALB_DNS}/');
define('DB_HOSTNAME', '$${DB_HOST}');
define('DB_USERNAME', '$${DB_USER}');
define('DB_PASSWORD', '$${DB_PASS}');
define('DB_DATABASE', '$${DB_NAME}');
CONFIG
```

---

### 11. Auto Scaling Group

```hcl
resource "aws_autoscaling_group" "main" {
  name                      = "${local.project_name}-asg"
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = [aws_lb_target_group.main.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300  # 5 minutes

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  depends_on = [
    aws_nat_gateway.main,
    aws_efs_mount_target.opencart,
    aws_db_instance.opencart
  ]
}
```

**Key Settings**:
- Minimum 2 instances for high availability
- 300s grace period for bootstrap completion
- Depends on NAT, EFS, and RDS being ready first

---

## Terraform Outputs

| Output | Description | Example Value |
|--------|-------------|---------------|
| `opencart_url` | Storefront URL | `http://vpc-masquerade-alb-123.us-east-1.elb.amazonaws.com` |
| `opencart_admin_url` | Admin panel URL | `.../admin` |
| `opencart_install_status_url` | Progress page | `.../install-status.php` |
| `bastion_ssh_command` | SSH command | `ssh -i bastion-key ubuntu@1.2.3.4` |
| `rds_endpoint` | Database endpoint | `vpc-masquerade-db.xxx.us-east-1.rds.amazonaws.com:3306` |
| `efs_id` | EFS ID | `fs-0abc123def456` |
| `asg_name` | ASG name | `vpc-masquerade-asg` |
| `sns_topic_arn` | SNS alerts topic | `arn:aws:sns:us-east-1:xxx:vpc-masquerade-alerts` |
| `cloudwatch_dashboard_url` | Dashboard URL | `https://console.aws.amazon.com/cloudwatch/...` |

---

## Deployment Flow

```
terraform init
     │
     ▼
terraform plan
     │ (validates config, shows changes)
     ▼
terraform apply
     │
     ├─► VPC, Subnets, IGW, NAT created
     │
     ├─► Security Groups created
     │
     ├─► Key Pair imported
     │
     ├─► EFS + Mount Targets created
     │
     ├─► RDS MySQL created (takes ~5-10 min)
     │
     ├─► Bastion Host launched (with SSM Agent)
     │
     ├─► ALB + Target Group + Listener created
     │
     ├─► Launch Template created
     │
     ├─► Monitoring (CloudWatch, SNS, CloudTrail) created
     │
     └─► ASG created → EC2 instances launch
              │
              └─► User Data executes on each instance
                       │
                       ├─► SSM Agent installed
                       ├─► health.php created (ALB healthy)
                       ├─► Packages installed
                       ├─► EFS mounted
                       ├─► OpenCart downloaded (first instance)
                       ├─► config.php generated
                       └─► Apache restarted
                              │
                              ▼
                    OpenCart is LIVE!
```

---

## Post-Deployment Manual Steps

After `terraform apply` completes:

1. **Access the storefront**: Visit the `opencart_url` output
2. **Access admin panel**: Visit `opencart_admin_url` (`.../admin`)
3. **Complete setup wizard** (if install directory wasn't removed):
   - Set admin username/password
   - Configure store name, email
4. **Configure store settings**:
   - Payment methods
   - Shipping options
   - Tax settings
   - Themes/extensions

---

## Monitoring (notes)

- CloudWatch Dashboard: centralized metrics for ALB, EC2 (ASG), RDS, and EFS.
- CloudWatch Alarms: ALB unhealthy hosts / 5xx, RDS CPU/storage/connections, ASG capacity, EFS credits — all wired to an SNS topic for email alerts.
- CloudTrail: API/audit logging delivered to an S3 bucket with:
  - **Versioning enabled**: Protects against accidental deletion (90-day version retention)
  - **Lifecycle policy**: Transition to Glacier after 30 days, expire after 365 days
- **AWS Backup for EFS**: Daily + Weekly backups with cold storage transition
- VPC Flow Logs: NOT ENABLED in this deployment.
  - Reason: AWS Learner Lab disallows creating the custom IAM role required for VPC Flow Logs and related resources. Attempting to create those IAM roles results in AccessDenied errors in the lab environment.
  - Alternative monitoring available in this setup:
    - ALB access logs (can be enabled to S3) for HTTP request-level visibility.
    - CloudWatch metrics and alarms (in place).
    - CloudTrail for API/audit events.
  - If you move to a full AWS account and want network-level logging:
    - Enable VPC Flow Logs and choose CloudWatch Logs or S3 as destination.
    - Ensure an appropriate IAM role/policy exists (not restricted by Learner Lab).
    - Consider lifecycle/retention policies for flow log storage to control cost.

---

## Backup Summary

| Component | Backup Type | Schedule | Retention | Cold Storage |
|-----------|------------|----------|-----------|--------------|
| **RDS MySQL** | Automated Snapshot | Daily 3 AM UTC | 7 days | N/A |
| **RDS MySQL** | Multi-AZ Standby | Real-time | Always | N/A |
| **RDS MySQL** | Final Snapshot | On deletion | Until deleted | N/A |
| **EFS** | AWS Backup (Daily) | Daily 5 AM UTC | 30 days | After 7 days |
| **EFS** | AWS Backup (Weekly) | Sunday 6 AM UTC | 90 days | No |
| **S3 CloudTrail** | Versioning | On change | 90 days (versions) | N/A |
| **S3 CloudTrail** | Lifecycle | Automatic | 365 days (logs) | After 30 days (Glacier) |

---

## Troubleshooting

### Connect via Session Manager (Recommended)
```bash
# No SSH key needed - use AWS Console
# EC2 → Instances → Select instance → Connect → Session Manager

# Or via AWS CLI
aws ssm start-session --target i-XXXXX --region us-east-1
```

### Connect via SSH (Alternative)
```bash
# Use SSH Agent Forwarding from local machine
ssh-add C:\path\to\bastion-key
ssh -A -i bastion-key ubuntu@<bastion-ip>
ssh ubuntu@<private-web-ip>
```

### Check User Data Logs
```bash
# View logs
sudo tail -f /var/log/user-data.log
```

### Check EFS Mount
```bash
df -h | grep efs
ls -la /var/www/html/opencart/
du -sh /var/www/html/opencart/
```

### Check Database Connection
```bash
# Use the password from your terraform.tfvars or the default in main.tf
mysql -h <rds-endpoint> -u ocadmin -p'<your_db_password>' -e "SHOW DATABASES;"
```

### Check SSM Agent Status
```bash
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
```

---

## Security Considerations

1. **Credentials Management**: All sensitive credentials (db_password, admin_password) are now:
   - ✅ Defined as Terraform variables with `sensitive = true`
   - ✅ Can be overridden via `terraform.tfvars` (add to .gitignore!)
   - ✅ Have validation rules (minimum length, complexity)
   - 📝 See [NOTE.md](NOTE.md) for full list of configurable variables

2. **HTTPS Support**: Implemented via Cloudflare Full SSL mode:
   - Self-signed TLS certificate on ALB
   - Cloudflare terminates user HTTPS → connects to ALB via HTTPS
   - OpenCart config.php detects Cloudflare `CF-Visitor` header for protocol detection
   - Apache configured to trust `X-Forwarded-Proto` header

3. **Disaster Recovery**:
   - RDS: 7-day automated backups + Multi-AZ + final snapshot on deletion
   - EFS: AWS Backup (daily 5AM + weekly Sunday) + encrypted at rest + lifecycle policy
   - S3: Versioning enabled (90-day) + Glacier transition (30 days) + expiration (365 days)
   - ⚠️ No cross-region replication (would add ~$50/month)

4. **Bastion Access**: SSH is open to 0.0.0.0/0. Restrict to specific IPs in production
