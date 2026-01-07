################################################################################
# OpenCart 3.0.5.0 - AWS Learner Lab Deployment (Ubuntu + Progress Page)
################################################################################

#############################################
# DATA SOURCES
#############################################

# Existing instance profile in Learner Lab
data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

# Ubuntu 22.04 LTS AMI (Jammy) from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

#############################################
# LOCALS
#############################################

locals {
  project_name = "masquerade-opencart"
  environment  = "production"

  # Network
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

  # Database credentials (from variables - never hardcode in production!)
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  db_port     = 3306

  # OpenCart Admin credentials (from variables)
  admin_username = var.opencart_admin_username
  admin_password = var.opencart_admin_password
  admin_email    = var.opencart_admin_email

  # EC2
  key_name = "bastion-key"

  opencart_version = "3.0.5.0"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    Application = "OpenCart"
  }
}

#############################################
# VPC & NETWORKING
#############################################

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = length(local.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

resource "aws_subnet" "private" {
  count             = length(local.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-gw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-rt"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

#############################################
# SECURITY GROUPS
#############################################

resource "aws_security_group" "bastion" {
  name        = "${local.project_name}-bastion-sg"
  description = "Allow SSH to bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.project_name}-bastion-sg" })
}

resource "aws_security_group" "alb" {
  name        = "${local.project_name}-alb-sg"
  description = "Allow HTTPS from Cloudflare only"
  vpc_id      = aws_vpc.main.id

  # Cloudflare IPv4 ranges (https://cloudflare.com/ips-v4)
  # Only allow HTTPS from Cloudflare - blocks direct ALB access
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [
      "173.245.48.0/20", 
      "103.21.244.0/22", 
      "103.22.200.0/22", 
      "103.31.4.0/22", 
      "141.101.64.0/18", 
      "108.162.192.0/18", 
      "190.93.240.0/20", 
      "188.114.96.0/20", 
      "197.234.240.0/22", 
      "198.41.128.0/17", 
      "162.158.0.0/15", 
      "104.16.0.0/13", 
      "104.24.0.0/14", 
      "172.64.0.0/13", 
      "131.0.72.0/22"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.project_name}-alb-sg" })
}

resource "aws_security_group" "web" {
  name        = "${local.project_name}-web-sg"
  description = "Web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.project_name}-web-sg" })
}

resource "aws_security_group" "efs" {
  name        = "${local.project_name}-efs-sg"
  description = "EFS from web"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "udp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.project_name}-efs-sg" })
}

resource "aws_security_group" "rds" {
  name        = "${local.project_name}-rds-sg"
  description = "MySQL from web/bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = local.db_port
    to_port   = local.db_port
    protocol  = "tcp"
    security_groups = [
      aws_security_group.web.id,
      aws_security_group.bastion.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.project_name}-rds-sg" })
}

#############################################
# KEY PAIR (Auto-generated for bastion → web server SSH)
#############################################

# Generate SSH key pair using Terraform
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096

  # Force key rotation by changing this value
  # Uncomment and change the value to force a new key generation
  # lifecycle {
  #   ignore_changes = []
  # }
}

resource "aws_key_pair" "bastion" {
  key_name   = "bastion-key"
  public_key = tls_private_key.bastion.public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-bastion-key"
  })
}

#############################################
# EFS
#############################################

resource "aws_efs_file_system" "opencart" {
  creation_token   = "${local.project_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  # Cost optimization: Move infrequently accessed files to cheaper storage
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS" # Move to Infrequent Access after 30 days
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS" # Move back when accessed
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-efs"
  })
}

resource "aws_efs_mount_target" "opencart" {
  count           = length(aws_subnet.private)
  file_system_id  = aws_efs_file_system.opencart.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

#############################################
# EFS BACKUP (AWS Backup)
#############################################

# Backup Vault for storing EFS backups
resource "aws_backup_vault" "opencart" {
  name = "${local.project_name}-backup-vault"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-backup-vault"
  })
}

# Backup Plan - Daily backups with 30-day retention
resource "aws_backup_plan" "efs" {
  name = "${local.project_name}-efs-backup-plan"

  rule {
    rule_name         = "daily-efs-backup"
    target_vault_name = aws_backup_vault.opencart.name
    schedule          = "cron(0 5 * * ? *)" # Daily at 5 AM UTC (after RDS backup)

    # Backup lifecycle - delete after 30 days (no cold storage for short retention)
    lifecycle {
      delete_after = 30
    }
  }

  # Weekly backup with longer retention
  rule {
    rule_name         = "weekly-efs-backup"
    target_vault_name = aws_backup_vault.opencart.name
    schedule          = "cron(0 6 ? * SUN *)" # Every Sunday at 6 AM UTC

    lifecycle {
      delete_after = 90 # Keep weekly backups for 90 days
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-efs-backup-plan"
  })
}

# Backup Selection - Select EFS for backup using LabRole
resource "aws_backup_selection" "efs" {
  name         = "${local.project_name}-efs-backup-selection"
  plan_id      = aws_backup_plan.efs.id
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  resources = [
    aws_efs_file_system.opencart.arn
  ]
}

#############################################
# RDS (MySQL)
#############################################

resource "aws_db_subnet_group" "opencart" {
  name       = "${local.project_name}-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rds-subnet-group"
  })
}

resource "aws_db_instance" "opencart" {
  identifier        = "${local.project_name}-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = local.db_name
  username = local.db_username
  password = local.db_password
  port     = local.db_port

  db_subnet_group_name   = aws_db_subnet_group.opencart.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = true

  # DISASTER RECOVERY: Automated backups
  backup_retention_period = 7                     # Keep 7 days of automated backups
  backup_window           = "03:00-04:00"         # Daily backup at 3 AM UTC
  maintenance_window      = "Mon:04:00-Mon:05:00" # Maintenance window after backup
  copy_tags_to_snapshot   = true
  deletion_protection     = false # Set to true in real production

  # Final snapshot before deletion (for safety)
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.project_name}-final-snapshot"

  tags = merge(local.common_tags, {
    Name     = "${local.project_name}-rds-mysql"
    Backup   = "Automated-7days"
    Critical = "true"
  })
}

# Redis removed - using Cloudflare CDN + ALB sticky sessions instead

#############################################
# BASTION
#############################################

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
    
    # Install SSM Agent for Session Manager access
    snap install amazon-ssm-agent --classic
    systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
    systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
    
    # Install private key for SSH access to web servers
    mkdir -p /home/ubuntu/.ssh
    cat > /home/ubuntu/.ssh/id_rsa << 'KEYEOF'
${tls_private_key.bastion.private_key_pem}
KEYEOF
    chmod 600 /home/ubuntu/.ssh/id_rsa
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh
  EOF

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-bastion"
  })

  depends_on = [aws_key_pair.bastion, tls_private_key.bastion]
}

#############################################
# LOAD BALANCER
#############################################

resource "aws_lb" "main" {
  name               = "${local.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb"
  })
}

resource "aws_lb_target_group" "main" {
  name     = "${local.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health.php"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 15
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Redirect all HTTP to HTTPS
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-http-listener"
  })
}

#############################################
# HTTPS SUPPORT - Self-Signed Certificate for Cloudflare Full SSL
#############################################

# Generate private key
resource "tls_private_key" "alb_cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate (valid for 1 year)
resource "tls_self_signed_cert" "alb_cert" {
  private_key_pem = tls_private_key.alb_cert.private_key_pem

  subject {
    common_name  = var.cloudflare_domain != "" ? var.cloudflare_domain : aws_lb.main.dns_name
    organization = "Masquerade OpenCart"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  # Include ALB DNS and Cloudflare domain in SAN
  dns_names = compact([
    aws_lb.main.dns_name,
    var.cloudflare_domain != "" ? var.cloudflare_domain : null,
    var.cloudflare_domain != "" ? "www.${var.cloudflare_domain}" : null,
  ])
}

# Import certificate to ACM
resource "aws_acm_certificate" "alb_cert" {
  private_key      = tls_private_key.alb_cert.private_key_pem
  certificate_body = tls_self_signed_cert.alb_cert.cert_pem

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-self-signed-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS Listener (for Cloudflare Full SSL mode)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-https-listener"
  })
}

#############################################
# LAUNCH TEMPLATE + USER DATA
#############################################

locals {
  # Cloudflare domain or fallback to ALB DNS
  site_domain = var.cloudflare_domain != "" ? var.cloudflare_domain : aws_lb.main.dns_name

  user_data_opencart = <<-EOT
#!/bin/bash
exec > >(tee /var/log/user-data.log) 2>&1

# Install SSM Agent first for Session Manager access
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

EFS_ID="${aws_efs_file_system.opencart.id}"
OC_VER="${local.opencart_version}"
DB_HOST="${aws_db_instance.opencart.address}"
DB_NAME="${local.db_name}"
DB_USER="${local.db_username}"
DB_PASS="${local.db_password}"
DB_PORT="${local.db_port}"
ALB="${aws_lb.main.dns_name}"
SITE_DOMAIN="${local.site_domain}"
ADMIN_USER="${local.admin_username}"
ADMIN_PASS="${local.admin_password}"
ADMIN_EMAIL="${local.admin_email}"
WEB="/var/www/html/opencart"
export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# Health check first
mkdir -p /var/www/html "$WEB"
echo "<?php echo 'OK'; ?>" > /var/www/html/health.php

log "Installing Apache+PHP..."
apt-get update -y && apt-get install -y apache2 software-properties-common curl unzip nfs-common wget mysql-client netcat-openbsd dnsutils
add-apt-repository ppa:ondrej/php -y && apt-get update -y
apt-get install -y php8.1 libapache2-mod-php8.1 php8.1-{mysql,gd,curl,zip,xml,mbstring,intl,bcmath,opcache}

# PHP config
sed -i 's/memory_limit = .*/memory_limit = 512M/;s/upload_max_filesize = .*/upload_max_filesize = 50M/;s/post_max_size = .*/post_max_size = 50M/' /etc/php/8.1/apache2/php.ini
mkdir -p /var/lib/php/sessions && chown www-data:www-data /var/lib/php/sessions
a2enmod rewrite headers && systemctl restart apache2

log "Waiting for RDS..."
for i in $(seq 1 30); do mysqladmin ping -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" --silent 2>/dev/null && break; sleep 10; done

log "Mounting EFS..."
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
EFS_DNS="$EFS_ID.efs.$AWS_REGION.amazonaws.com"

# Ensure NFS services are running
systemctl start rpcbind || true
systemctl enable rpcbind || true

# Wait for EFS DNS to resolve (can take a few minutes after mount target creation)
log "Waiting for EFS DNS resolution..."
for i in $(seq 1 40); do
  if nslookup "$EFS_DNS" >/dev/null 2>&1; then
    log "EFS DNS resolved successfully"
    break
  fi
  log "Waiting for EFS DNS... attempt $i/40"
  sleep 15
done

# Test EFS mount target connectivity
log "Testing EFS connectivity..."
for i in $(seq 1 20); do
  if nc -zw5 "$EFS_DNS" 2049 2>/dev/null; then
    log "EFS port 2049 is reachable"
    break
  fi
  log "Waiting for EFS connectivity... attempt $i/20"
  sleep 10
done

# Mount EFS with retries
MOUNT_SUCCESS=false
log "Attempting to mount EFS..."
for i in $(seq 1 30); do
  if mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport "$EFS_DNS:/" "$WEB" 2>&1; then
    log "EFS mounted successfully on attempt $i"
    MOUNT_SUCCESS=true
    break
  fi
  log "Mount attempt $i failed, retrying in 15 seconds..."
  sleep 15
done

# Verify mount and add to fstab
if mountpoint -q "$WEB"; then
  log "EFS is mounted at $WEB"
  # Add to fstab for persistence across reboots
  grep -q "$EFS_DNS" /etc/fstab || echo "$EFS_DNS:/ $WEB nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >> /etc/fstab
  MOUNT_SUCCESS=true
else
  log "ERROR: EFS mount failed after all attempts!"
  log "Trying alternative mount with amazon-efs-utils..."
  # Install amazon-efs-utils as fallback
  apt-get install -y git binutils rustc cargo pkg-config libssl-dev
  git clone https://github.com/aws/efs-utils /tmp/efs-utils
  cd /tmp/efs-utils && ./build-deb.sh
  apt-get install -y ./build/amazon-efs-utils*deb
  
  # Try mounting with efs helper
  mount -t efs -o tls "$EFS_ID:/" "$WEB" 2>&1 && MOUNT_SUCCESS=true
fi

if [ "$MOUNT_SUCCESS" = "false" ]; then
  log "CRITICAL: All EFS mount attempts failed. Check security groups and mount targets."
fi

log "Installing OpenCart..."
(
flock -x -w 300 200 || true
if [ ! -f "$WEB/index.php" ]; then
  cd /tmp && rm -rf oc && mkdir oc && cd oc
  curl -fSL --retry 3 "https://github.com/opencart/opencart/releases/download/$OC_VER/opencart-$OC_VER.zip" -o oc.zip || \
    wget -q "https://github.com/opencart/opencart/releases/download/$OC_VER/opencart-$OC_VER.zip" -O oc.zip
  unzip -q oc.zip
  UP=$(find . -type d -name upload -print -quit)
  [ -n "$UP" ] && cp -rf "$UP"/* "$WEB/"
  [ -f "$WEB/config-dist.php" ] && mv "$WEB/config-dist.php" "$WEB/config.php"
  [ -f "$WEB/admin/config-dist.php" ] && mv "$WEB/admin/config-dist.php" "$WEB/admin/config.php"
  mkdir -p "$WEB/system/storage"/{cache,download,logs,modification,session,upload}

  # HTTPS-aware config.php (detects Cloudflare headers for protocol)
  cat > "$WEB/config.php" << 'EOFCONFIG'
<?php
// Detect HTTPS from Cloudflare CF-Visitor header or X-Forwarded-Proto
$is_https = (
    (!empty($_SERVER['HTTP_CF_VISITOR']) && strpos($_SERVER['HTTP_CF_VISITOR'], 'https') !== false) ||
    (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ||
    (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
);
$protocol = $is_https ? 'https://' : 'http://';
EOFCONFIG

  cat >> "$WEB/config.php" << EOF
define('HTTP_SERVER', \$protocol . '$SITE_DOMAIN/');
define('HTTPS_SERVER', 'https://$SITE_DOMAIN/');
define('DIR_APPLICATION', '$WEB/catalog/');
define('DIR_SYSTEM', '$WEB/system/');
define('DIR_IMAGE', '$WEB/image/');
define('DIR_STORAGE', '$WEB/system/storage/');
define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
define('DIR_TEMPLATE', DIR_APPLICATION . 'view/theme/');
define('DIR_CONFIG', DIR_SYSTEM . 'config/');
define('DIR_CACHE', DIR_STORAGE . 'cache/');
define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');
define('DIR_LOGS', DIR_STORAGE . 'logs/');
define('DIR_MODIFICATION', DIR_STORAGE . 'modification/');
define('DIR_SESSION', DIR_STORAGE . 'session/');
define('DIR_UPLOAD', DIR_STORAGE . 'upload/');
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '$DB_HOST');
define('DB_USERNAME', '$DB_USER');
define('DB_PASSWORD', '$DB_PASS');
define('DB_DATABASE', '$DB_NAME');
define('DB_PORT', '$DB_PORT');
define('DB_PREFIX', 'oc_');
EOF

  # HTTPS-aware admin/config.php
  cat > "$WEB/admin/config.php" << 'EOFCONFIG'
<?php
// Detect HTTPS from Cloudflare CF-Visitor header or X-Forwarded-Proto
$is_https = (
    (!empty($_SERVER['HTTP_CF_VISITOR']) && strpos($_SERVER['HTTP_CF_VISITOR'], 'https') !== false) ||
    (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ||
    (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
);
$protocol = $is_https ? 'https://' : 'http://';
EOFCONFIG

  cat >> "$WEB/admin/config.php" << EOF
define('HTTP_SERVER', \$protocol . '$SITE_DOMAIN/admin/');
define('HTTP_CATALOG', \$protocol . '$SITE_DOMAIN/');
define('HTTPS_SERVER', 'https://$SITE_DOMAIN/admin/');
define('HTTPS_CATALOG', 'https://$SITE_DOMAIN/');
define('DIR_APPLICATION', '$WEB/admin/');
define('DIR_SYSTEM', '$WEB/system/');
define('DIR_IMAGE', '$WEB/image/');
define('DIR_STORAGE', '$WEB/system/storage/');
define('DIR_CATALOG', '$WEB/catalog/');
define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');
define('DIR_CONFIG', DIR_SYSTEM . 'config/');
define('DIR_CACHE', DIR_STORAGE . 'cache/');
define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');
define('DIR_LOGS', DIR_STORAGE . 'logs/');
define('DIR_MODIFICATION', DIR_STORAGE . 'modification/');
define('DIR_SESSION', DIR_STORAGE . 'session/');
define('DIR_UPLOAD', DIR_STORAGE . 'upload/');
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '$DB_HOST');
define('DB_USERNAME', '$DB_USER');
define('DB_PASSWORD', '$DB_PASS');
define('DB_DATABASE', '$DB_NAME');
define('DB_PORT', '$DB_PORT');
define('DB_PREFIX', 'oc_');
EOF

  chown -R www-data:www-data "$WEB" && chmod -R 755 "$WEB"
  # Use production admin credentials from variables
  [ -f "$WEB/install/cli_install.php" ] && php "$WEB/install/cli_install.php" install \
    --db_driver mysqli --db_hostname "$DB_HOST" --db_username "$DB_USER" --db_password "$DB_PASS" \
    --db_database "$DB_NAME" --db_port "$DB_PORT" --db_prefix oc_ \
    --username "$ADMIN_USER" --password "$ADMIN_PASS" --email "$ADMIN_EMAIL" --http_server "https://$SITE_DOMAIN/"
  rm -rf "$WEB/install"
fi
) 200>/var/lock/oc.lock

echo "<?php echo 'OK'; ?>" > "$WEB/health.php"

# Apache config with Cloudflare header forwarding
cat > /etc/apache2/sites-available/opencart.conf << 'EOF'
<VirtualHost *:80>
    DocumentRoot /var/www/html/opencart
    
    # Trust Cloudflare/ALB headers for HTTPS detection
    SetEnvIf X-Forwarded-Proto "https" HTTPS=on
    
    # Also set this as a request header for PHP to read
    RequestHeader set X-Forwarded-Proto "https" env=HTTPS
    
    <Directory /var/www/html/opencart>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    Alias /health.php /var/www/html/health.php
    ErrorLog $${APACHE_LOG_DIR}/error.log
    CustomLog $${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
a2enmod headers  # Make sure headers module is enabled
a2dissite 000-default.conf 2>/dev/null; a2ensite opencart.conf; systemctl restart apache2
log "Done! URL: https://$SITE_DOMAIN/"
  EOT
}

resource "aws_launch_template" "main" {
  name_prefix   = "${local.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = local.key_name

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab_profile.name
  }

  network_interfaces {
    security_groups             = [aws_security_group.web.id]
    associate_public_ip_address = false
  }

  user_data = base64encode(local.user_data_opencart)

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.project_name}-web"
      Role = "OpenCartWeb"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

#############################################
# AUTO SCALING GROUP
#############################################

resource "aws_autoscaling_group" "main" {
  name                      = "${local.project_name}-asg"
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = [aws_lb_target_group.main.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 600

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

#############################################
# AUTO SCALING POLICIES
#############################################

# Scale UP policy (adds 1 instance)
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${local.project_name}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300 # 5 min cooldown before next scaling action
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# Scale DOWN policy (removes 1 instance)
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${local.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300 # 5 min cooldown before next scaling action
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# SCALE UP TRIGGER 1: CPU > 70% for 10 minutes (gradual response)
# Evaluates: 2 periods × 5 min = 10 min sustained high CPU
resource "aws_cloudwatch_metric_alarm" "cpu_high_gradual" {
  alarm_name          = "${local.project_name}-cpu-high-70"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up when CPU > 70% for 10 minutes (gradual response)"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-cpu-high-70"
  })
}

# SCALE UP TRIGGER 2: CPU > 90% for 2 minutes (urgent response)
# Evaluates: 2 periods × 1 min = 2 min critical CPU
resource "aws_cloudwatch_metric_alarm" "cpu_critical_urgent" {
  alarm_name          = "${local.project_name}-cpu-critical-90"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60 # 1 minute
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Scale up URGENTLY when CPU > 90% for 2 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-cpu-critical-90"
  })
}

# SCALE DOWN TRIGGER: CPU < 50% for 15 minutes (conservative)
# Evaluates: 3 periods × 5 min = 15 min sustained low CPU
# Longer period to prevent flapping (scaling up/down repeatedly)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.project_name}-cpu-low-50"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = 50
  alarm_description   = "Scale down when CPU < 50% for 15 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-cpu-low-50"
  })
}

#############################################
# MONITORING - SNS Topic for Alerts
#############################################

resource "aws_sns_topic" "alerts" {
  name = "${local.project_name}-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

#############################################
# MONITORING - CloudWatch Alarms
#############################################

# ALB Unhealthy Hosts Alarm
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${local.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Triggers when there are unhealthy hosts in the ALB target group"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.main.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-unhealthy-hosts-alarm"
  })
}

# ALB High Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${local.project_name}-alb-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Triggers when ALB response time exceeds 5 seconds"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-response-time-alarm"
  })
}

# ALB 5XX Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${local.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Triggers when ALB returns more than 10 5XX errors in 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-5xx-errors-alarm"
  })
}

# RDS CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when RDS CPU exceeds 80%"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.opencart.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rds-cpu-alarm"
  })
}

# RDS Free Storage Space Alarm
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.project_name}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2GB in bytes
  alarm_description   = "Triggers when RDS free storage falls below 2GB"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.opencart.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rds-storage-alarm"
  })
}

# RDS Database Connections Alarm
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${local.project_name}-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 50
  alarm_description   = "Triggers when RDS connections exceed 50"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.opencart.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rds-connections-alarm"
  })
}

# ASG - Auto Scaling Group Size Alarm (Low capacity warning)
resource "aws_cloudwatch_metric_alarm" "asg_low_capacity" {
  alarm_name          = "${local.project_name}-asg-low-capacity"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "Triggers when ASG has fewer than 2 healthy instances"
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-asg-low-capacity-alarm"
  })
}

# EFS - Burst Credit Balance Alarm
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  alarm_name          = "${local.project_name}-efs-low-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000000000 # 1TB of burst credits
  alarm_description   = "Triggers when EFS burst credits fall below 1TB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.opencart.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-efs-burst-credits-alarm"
  })
}

#############################################
# MONITORING - CloudWatch Dashboard
#############################################

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Response Time"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Average", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB Healthy/Unhealthy Hosts"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Average", period = 60 }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Average", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU Utilization"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.opencart.identifier, { stat = "Average", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "RDS Database Connections"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.opencart.identifier, { stat = "Average", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "RDS Free Storage Space (GB)"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.opencart.identifier, { stat = "Average", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "ASG In-Service Instances"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.main.name, { stat = "Average", period = 60 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "EFS Client Connections"
          region = data.aws_availability_zones.available.id
          metrics = [
            ["AWS/EFS", "ClientConnections", "FileSystemId", aws_efs_file_system.opencart.id, { stat = "Sum", period = 60 }]
          ]
          view = "timeSeries"
        }
      }
    ]
  })
}

#############################################
# MONITORING - CloudTrail (Audit Logging)
#############################################

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.project_name}-cloudtrail-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-cloudtrail-logs"
  })
}

# S3 Versioning for CloudTrail logs protection
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Lifecycle Policy for cost optimization (delete old versions after 90 days)
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {} # Apply to all objects

    # Delete non-current versions after 90 days
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Delete expired delete markers
    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    filter {} # Apply to all objects

    # Move logs older than 30 days to Glacier for cost savings
    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # Delete logs after 365 days
    expiration {
      days = 365
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail]
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.project_name}-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.project_name}-trail"
          }
        }
      }
    ]
  })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudtrail" "main" {
  name                          = "${local.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-trail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

#############################################
# AUTO-EXPORT BASTION SSH KEY
#############################################

# Automatically save the bastion private key AND public key after apply
# IMPORTANT: Both files must be saved together to prevent SSH authentication failures
# caused by OpenSSH reading a stale .pub file from a previous deployment
# NOTE: Uses local_file resources instead of inline key interpolation to avoid
# exposing key patterns in the Terraform source code
resource "local_sensitive_file" "bastion_private_key" {
  content         = tls_private_key.bastion.private_key_pem
  filename        = "${path.module}/bastion-key"
  file_permission = "0400"
}

resource "local_file" "bastion_public_key" {
  content         = tls_private_key.bastion.public_key_openssh
  filename        = "${path.module}/bastion-key.pub"
  file_permission = "0644"
}

#############################################
# OUTPUTS
#############################################

output "opencart_url" {
  description = "OpenCart storefront URL (HTTPS via Cloudflare)"
  value       = var.cloudflare_domain != "" ? "https://${var.cloudflare_domain}" : "https://${aws_lb.main.dns_name}"
}

output "opencart_url_http" {
  description = "OpenCart storefront URL (HTTP - use for testing without Cloudflare)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "opencart_admin_url" {
  description = "OpenCart admin URL (HTTPS via Cloudflare)"
  value       = var.cloudflare_domain != "" ? "https://${var.cloudflare_domain}/admin" : "https://${aws_lb.main.dns_name}/admin"
}

output "alb_dns_name" {
  description = "ALB DNS name (point Cloudflare CNAME to this)"
  value       = aws_lb.main.dns_name
}

output "bastion_ssh_command" {
  description = "SSH command for bastion (key is auto-saved after apply)"
  value       = "ssh -i bastion-key ubuntu@${aws_instance.bastion.public_ip}"
}

output "bastion_public_ip" {
  description = "Bastion host public IP address"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_key" {
  description = "Private key for SSH access (auto-saved to bastion-key file)"
  value       = tls_private_key.bastion.private_key_pem
  sensitive   = true
}

output "bastion_key_fingerprint" {
  description = "SSH key fingerprint - verify this matches your bastion-key file"
  value       = tls_private_key.bastion.public_key_fingerprint_sha256
}

output "manual_key_export_command" {
  description = "Manual key export (only if auto-export failed)"
  value       = "$s = Get-Content terraform.tfstate -Raw | ConvertFrom-Json; $s.outputs.bastion_private_key.value | Set-Content bastion-key -NoNewline; icacls bastion-key /inheritance:r /grant \"$($env:USERNAME):R\""
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.opencart.endpoint
}

output "efs_id" {
  description = "EFS filesystem ID"
  value       = aws_efs_file_system.opencart.id
}

output "asg_name" {
  description = "Autoscaling group name"
  value       = aws_autoscaling_group.main.name
}

#############################################
# DISASTER RECOVERY OUTPUTS
#############################################

output "rds_backup_retention" {
  description = "RDS automated backup retention period"
  value       = "${aws_db_instance.opencart.backup_retention_period} days"
}

output "rds_multi_az" {
  description = "RDS Multi-AZ status"
  value       = aws_db_instance.opencart.multi_az ? "Enabled (automatic failover)" : "Disabled"
}

output "efs_encrypted" {
  description = "EFS encryption status"
  value       = aws_efs_file_system.opencart.encrypted ? "Encrypted at rest" : "Not encrypted"
}

output "efs_backup_vault" {
  description = "AWS Backup vault for EFS backups"
  value       = aws_backup_vault.opencart.name
}

output "efs_backup_plan" {
  description = "AWS Backup plan for EFS (daily + weekly backups)"
  value       = aws_backup_plan.efs.name
}

output "s3_versioning_enabled" {
  description = "S3 CloudTrail bucket versioning status"
  value       = "Enabled (90-day version retention)"
}

#############################################
# MONITORING OUTPUTS
#############################################

output "sns_topic_arn" {
  description = "SNS Topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "cloudtrail_bucket" {
  description = "S3 bucket for CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_name" {
  description = "CloudTrail trail name"
  value       = aws_cloudtrail.main.name
}
