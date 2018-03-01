provider "aws" {
  region="eu-west-1"
}

data "template_file" "app_init" {
  template = "${file("./scripts/app_user_data.sh")}"
  vars {
    mongodb_ip = "${module.db-tier.private_ip}"
  }
}

resource "aws_vpc" "app_vpc1" {
  cidr_block            = "10.22.0.0/16"
  enable_dns_support    = true
  enable_dns_hostnames  = true
  instance_tenancy      = "default"

	tags {
		Name = "dragos-app-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.app_vpc1.id}"

  tags {
    Name = "dragos-app-gateway"
  }
}

resource "aws_route_table" "r" {
  vpc_id = "${aws_vpc.app_vpc1.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags{
    Name = "dragos-gateway-public"
  }
}

module "app-tier" {
  name = "app-dragos-tier"
  source = "./modules/tier"
  vpc_id = "${aws_vpc.app_vpc1.id}"
  machine_count = 2
  route_table_id = "${aws_route_table.r.id}"
  cidr_block = "10.22.1.0/24"
  user_data = "${data.template_file.app_init.rendered}"
  ami_id = "ami-24b0db5d"
  map_public_ip_on_launch = true

  ingress = [{
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = "0.0.0.0/0"
    }]
}

module "db-tier" {
  name = "db-dragos-tier"
  source = "./modules/tier"
  vpc_id = "${aws_vpc.app_vpc1.id}"
  route_table_id = "${aws_vpc.app_vpc1.main_route_table_id}"
  cidr_block = "10.22.2.0/24"
  user_data = ""
  machine_count = 1
  ami_id = "ami-c69bf0bf"

  ingress = [{
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = "${module.app-tier.subnet_cidr_block}"
    }]
}

# Create a new load balancer
resource "aws_elb" "dragos-elb" {
  name               = "dragos-terraform-elb"

  listener {
    instance_port     = 3000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:3000/"
    interval            = 10
  }

  subnets            = ["${module.app-tier.app_subnet}"]
  security_groups    = ["${module.app-tier.sec_group}"]
  instances          = ["${module.app-tier.app_id}"]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags {
    Name = "dragos-terraform-elb"
  }
}

