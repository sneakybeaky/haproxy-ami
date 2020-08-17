terraform {
  required_version = "~>0.11"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY AN EC2 INSTANCE THAT RUNS A SIMPLE RUBY WEB APP BUILT USING A PACKER TEMPLATE
# See test/terraform_packer_example.go for how to write automated tests for this code.
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = "${var.aws_region}"
}

data "aws_vpc" "build" {
  id = "vpc-09098752f0701b2b4"
}

data "aws_subnet_ids" "sog_connected" {
  vpc_id = "${data.aws_vpc.build.id}"
}

# The public IP address of the machine terraform was invoked from.
# Used to whitelist ports for testing
data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE EC2 INSTANCE WITH HAPROXY
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_instance" "haproxy" {
  associate_public_ip_address = true
  ami                         = "${var.ami_id}"
  instance_type               = "m5.large"
  vpc_security_group_ids      = ["${aws_security_group.haproxy.id}"]
  subnet_id                   = "${data.aws_subnet_ids.sog_connected.ids[0]}"

  iam_instance_profile = "${aws_iam_instance_profile.test_profile.name}"

  tags {
    Name = "${var.instance_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP TO CONTROL WHAT REQUESTS CAN GO IN AND OUT OF THE EC2 INSTANCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "haproxy" {
  name   = "${var.instance_name}"
  vpc_id = "${data.aws_vpc.build.id}"

  ingress {
    from_port = "${var.stats_port}"
    to_port   = "${var.stats_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    from_port = "${var.dtax_healthcheck_port}"
    to_port   = "${var.dtax_healthcheck_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    from_port = "${var.itax_healthcheck_port}"
    to_port   = "${var.itax_healthcheck_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    from_port = "${var.dtax_port}"
    to_port   = "${var.dtax_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    from_port = "${var.itax_port}"
    to_port   = "${var.itax_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    from_port = "${var.haproxy_exporter_port}"
    to_port   = "${var.haproxy_exporter_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    from_port = "${var.node_export_port}"
    to_port   = "${var.node_export_port}"
    protocol  = "tcp"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "test_profile" {
  name = "${var.prefix}_profile"
  role = "${aws_iam_role.test.name}"
}

resource "aws_iam_role" "test" {
  name = "${var.prefix}_test_role"
  path = "/"

  assume_role_policy = "${data.aws_iam_policy_document.assume_role.json}"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    effect = "Allow"
  }
}

data "aws_iam_policy_document" "session_manager" {
  statement {
    actions = ["ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]

    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions = ["s3:GetEncryptionConfiguration"]

    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "test_policy" {
  name = "${var.instance_name}-test_policy"
  role = "${aws_iam_role.test.id}"

  policy = "${data.aws_iam_policy_document.session_manager.json}"
}

data "aws_iam_policy" "CloudWatchAgentServerPolicy" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch-role-policy-attach" {
  role       = "${aws_iam_role.test.name}"
  policy_arn = "${data.aws_iam_policy.CloudWatchAgentServerPolicy.arn}"
}
