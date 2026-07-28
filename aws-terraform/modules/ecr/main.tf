# =============================================================================
# ecr module
# =============================================================================
# Creates one ECR repository per CloudKitchen microservice via for_each.
# Each repository:
#   * scans images on push for CVEs
#   * encrypts at rest with AES256
#   * applies a lifecycle policy that keeps only the most recent N images,
#     expiring older ones to control storage cost
# =============================================================================

resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${var.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}/${each.value}"
    Service = each.value
  })
}

# Keep only the most recent N images; expire anything older.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
