# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# VPC using Coalfire module
module "vpc" {
  source = "git::https://github.com/Coalfire-CF/terraform-aws-vpc-nfw.git?ref=v3.1.0"

  vpc_name = "${var.resource_prefix}-vpc"
  cidr     = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  subnets = [
    {
      tag               = "public-1"
      cidr              = var.public_subnet_cidrs[0]
      type              = "public"
      availability_zone = data.aws_availability_zones.available.names[0]
    },
    {
      tag               = "public-2"
      cidr              = var.public_subnet_cidrs[1]
      type              = "public"
      availability_zone = data.aws_availability_zones.available.names[1]
    },
    {
      tag               = "private-1"
      cidr              = var.private_subnet_cidrs[0]
      type              = "private"
      availability_zone = data.aws_availability_zones.available.names[0]
    },
    {
      tag               = "private-2"
      cidr              = var.private_subnet_cidrs[1]
      type              = "private"
      availability_zone = data.aws_availability_zones.available.names[1]
    }
  ]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true

  flow_log_destination_type = "cloud-watch-logs"
  cloudwatch_log_group_retention_in_days = 30

  tags = var.tags
}

# S3 Buckets using Coalfire modules
module "images_bucket" {
  source = "git::https://github.com/Coalfire-CF/terraform-aws-s3.git?ref=v1.0.6"

  name                                 = "${var.resource_prefix}-images"
  enable_lifecycle_configuration_rules = true
  lifecycle_configuration_rules = [
    {
      id      = "archive-folder"
      prefix  = "archive/"
      enabled = true

      enable_glacier_transition            = true
      enable_current_object_expiration     = false
      enable_noncurrent_version_expiration = true

      glacier_transition_days                    = 90
      noncurrent_version_glacier_transition_days = 90
      noncurrent_version_expiration_days         = 365
    }
  ]

  enable_kms                    = true
  enable_server_side_encryption = true
  versioning                    = true

  tags = var.tags
}

module "logs_bucket" {
  source = "git::https://github.com/Coalfire-CF/terraform-aws-s3.git?ref=v1.0.6"

  name                                 = "${var.resource_prefix}-logs"
  enable_lifecycle_configuration_rules = true
  lifecycle_configuration_rules = [
    {
      id      = "active-logs"
      prefix  = "active/"
      enabled = true

      enable_glacier_transition            = true
      enable_current_object_expiration     = false
      enable_noncurrent_version_expiration = true

      glacier_transition_days                    = 90
      noncurrent_version_glacier_transition_days = 90
      noncurrent_version_expiration_days         = 365
    },
    {
      id      = "inactive-logs"
      prefix  = "inactive/"
      enabled = true

      enable_current_object_expiration     = true
      enable_noncurrent_version_expiration = true

      expiration_days                            = 90
      noncurrent_version_glacier_transition_days = 30
      noncurrent_version_expiration_days         = 90
    }
  ]

  enable_kms                    = true
  enable_server_side_encryption = true
  versioning                    = true

  tags = var.tags
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${var.resource_prefix}-alb-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-alb-sg"
  })
}

resource "aws_security_group" "asg_ec2" {
  name_prefix = "${var.resource_prefix}-asg-ec2-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-asg-ec2-sg"
  })
}

resource "aws_security_group" "standalone_ec2" {
  name_prefix = "${var.resource_prefix}-standalone-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}standalone-sg"
  })
}

# IAM Roles
resource "aws_iam_role" "ec2_role" {
  name = "${var.resource_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "s3_access" {
  name = "${var.resource_prefix}-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.images_bucket.arn,
          "${module.images_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${module.logs_bucket.arn}/*"
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.resource_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = var.tags
}

# User Data Script
locals {
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd mod_ssl openssl
    
    # Generate self-signed certificate
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
      -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
      -keyout /etc/pki/tls/private/localhost.key \
      -out /etc/pki/tls/certs/localhost.crt
    
    # Create index page
    echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
    echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
    echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
    echo "<p>Protocol: HTTPS on port 443</p>" >> /var/www/html/index.html
    
    # Start services
    systemctl start httpd
    systemctl enable httpd
  EOF
  )
}

# Standalone EC2 Instance in Sub2 (public subnet)
resource "aws_instance" "standalone" {
  ami                    = data.aws_ami.rhel.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = values(module.vpc.public_subnets)[1]
  vpc_security_group_ids = [aws_security_group.standalone_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = local.user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-standalone-instance"
  })
}

# Launch Template for ASG
resource "aws_launch_template" "asg" {
  name_prefix   = "${var.resource_prefix}-asg-"
  image_id      = data.aws_ami.rhel.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.asg_ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = local.user_data

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.resource_prefix}-asg-instance"
    })
  }

  tags = var.tags
}

# Auto Scaling Group
resource "aws_autoscaling_group" "main" {
  name                = "${var.resource_prefix}-asg"
  vpc_zone_identifier = values(module.vpc.private_subnets)
  target_group_arns   = [aws_lb_target_group.main.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = 2
  max_size         = 6
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.asg.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.resource_prefix}-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.resource_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = values(module.vpc.public_subnets)

  enable_deletion_protection = false

  tags = var.tags
}

resource "aws_lb_target_group" "main" {
  name     = "${var.resource_prefix}-tg-https"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = var.tags
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = var.tags
}
