resource "aws_iam_role" "main" {
  name = "ec2-role-valheim-server"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the IAM role
resource "aws_iam_role_policy" "ec2_policy" {
  role = aws_iam_role.main.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "ssm:PutParameter",
          "ssm:GetParameter"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Create an instance profile for the IAM role
resource "aws_iam_instance_profile" "main" {
  name = "ec2-instance-profile-valheim-server"
  role = aws_iam_role.main.name
}

# Define the EC2 instance with the IAM role
resource "aws_instance" "main" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.medium"
  subnet_id            = aws_subnet.public.id
  key_name             = aws_key_pair.main.key_name
  security_groups      = [aws_security_group.main.id]
  iam_instance_profile = aws_iam_instance_profile.main.name

  user_data = file("./scripts/valheim.sh")

  lifecycle {
    ignore_changes = [
      security_groups
    ]
  }
}

resource "aws_ebs_volume" "main" {
  availability_zone = "sa-east-1a"
  size              = 8
  tags = {
    Name = "valheim-volume"
  }
}

resource "aws_volume_attachment" "main" {
  device_name = "/dev/sdf"
  instance_id = aws_instance.main.id
  volume_id   = aws_ebs_volume.main.id
}
