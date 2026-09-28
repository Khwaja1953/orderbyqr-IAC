resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name = "${var.project_name}-${var.environment}-${each.value}"
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
  }
}