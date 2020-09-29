resource "aws_db_instance" "Postgres_RDS" {
  allocated_storage           = "${var.Postgres_RDS_Allocated_Storage}"
  engine                      = "postgres"
  storage_type                = "db.t2.large"
  engine_version              = "9.6.9"
  parameter_group_name        = "${aws_db_parameter_group.Postgres_RDS_Param_Group.name}"
  instance_class              = "${var.Postgres_RDS_Instance_Class}"
  name                        = "${var.Postgres_RDS_Name}"
  username                    = "${var.Postgres_RDS_DB_Username}"
  password                    = "${var.Postgres_RDS_DB_Password}"
  db_subnet_group_name        = "${aws_db_subnet_group.RDS_Subnet_Group.id}"
  vpc_security_group_ids      = ["${aws_security_group.Database_SG.id}"]
  skip_final_snapshot         = true
  multi_az                    = true
  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true
}
resource "aws_db_parameter_group" "Postgres_RDS_Param_Group" {
  name        = "${var.Postgres_RDS_Name}-parameter-group"
  family      = "postgres9.6.9"
  parameter {
    name  = "character_set_server"
    value = "utf8"
  }
  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}
resource "aws_instance" "EC2_App" {
  count                  = "${var.Compute_Resource_Count}"
  ami                    = "${data.aws_ami.Latest_Ubuntu_18_04_AMI.id}"
  instance_type          = "${var.EC2_App_Type}"
  key_name               = "${var.EC2_App_Key_Pair_Name}"
  vpc_security_group_ids = ["${aws_security_group.Application_SG.id}"]
  subnet_id              = "${element(aws_subnet.Aws_Private_Subnets.*.id, count.index)}"
  ebs_block_device {
      device_name        = "/dev/sdf"
      volume_type        = "gp2"
      volume_size        = "${var.EC2_App_EBS_Volume_Size}"
  }
  volume_tags {
      Name = "${var.EC2_App_Name_Tag}-EBS-Volume-${count.index}"
  }

  tags  {
    Name = "${var.EC2_App_Name_Tag}-Instance-${count.index}"
  }
}
resource "aws_s3_bucket" "Load_Balancer_AccessLogs_Bucket" {
  bucket = "${var.Load_Balancer_AccessLogs_Bucket_Name}"
  acl    = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "AES256"
      }
    }
  }
}
resource "aws_alb" "Load_Balancer" {
  name            = "${var.Load_Balancer_Name}"
  subnets         = ["${aws_subnet.Aws_Public_Subnets.*.id}"]
  security_groups = ["${aws_security_group.ALB_SG.id}"]
  access_logs {
    enabled = true
    bucket  = "${aws_s3_bucket.Load_Balancer_AccessLogs_Bucket.id}"
    prefix  = "${var.Load_Balancer_Name}-logs"
  }
}
resource "aws_alb_target_group" "Load_Balancer_Target_Group" {
  name        = "${var.Load_Balancer_Target_Group_Name}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.Aws_VPC.id}"
  target_type = "instance"

  health_check {
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:80/"
    interval            = 30
  }

}
resource "aws_alb_target_group_attachment" "Load_Balancer_Target_Group_Attachment" {
  count            = "${var.Compute_Resource_Count}"
  target_group_arn = "${aws_alb_target_group.Load_Balancer_Target_Group.arn}"
  target_id        = "${element(aws_instance.EC2_App.*.id, count.index)}"
}
resource "aws_alb_listener" "Load_Balancer_HTTP_Front_End" {
  load_balancer_arn = "${aws_alb.Load_Balancer.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.Load_Balancer_Target_Group.id}"
    type             = "forward"
  }
}
