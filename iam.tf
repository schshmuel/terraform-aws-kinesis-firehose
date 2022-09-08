locals {
  role_name = var.create_role ? coalesce(var.role_name, var.name, "*") : null
}

data "aws_iam_policy_document" "assume_role" {
  count = var.create_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  count                 = var.create_role ? 1 : 0
  name                  = local.role_name
  description           = var.role_description
  path                  = var.role_path
  force_detach_policies = var.role_force_detach_policies
  permissions_boundary  = var.role_permissions_boundary
  assume_role_policy    = data.aws_iam_policy_document.assume_role[0].json
  tags                  = merge(var.tags, var.role_tags)
}

##################
# Lambda
##################
data "aws_iam_policy_document" "lambda" {
  count = var.create_role && local.enable_transformation ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
      "lambda:GetFunctionConfiguration"
    ]
    resources = [var.transform_lambda_arn]
  }
}

resource "aws_iam_policy" "lambda" {
  count = var.create_role && local.enable_transformation ? 1 : 0

  name   = "${local.role_name}-lambda"
  path   = var.policy_path
  policy = data.aws_iam_policy_document.lambda[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda" {
  count = var.create_role && local.enable_transformation ? 1 : 0

  role       = aws_iam_role.firehose[0].name
  policy_arn = aws_iam_policy.lambda[0].arn
}

##################
# Glue
##################
data "aws_iam_policy_document" "glue" {
  count = var.create_role && var.enable_data_format_conversion && var.data_format_conversion_glue_use_existing_role ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetTableVersion",
      "glue:GetTableVersions"
    ]
    resources = [
      "arn:aws:glue:${local.data_format_conversion_glue_region}:${data.aws_caller_identity.current[0].account_id}:catalog",
      "arn:aws:glue:${local.data_format_conversion_glue_region}:${data.aws_caller_identity.current[0].account_id}:database/${var.data_format_conversion_glue_database}",
      "arn:aws:glue:${local.data_format_conversion_glue_region}:${data.aws_caller_identity.current[0].account_id}:table/${var.data_format_conversion_glue_database}/${var.data_format_conversion_glue_table_name}"
    ]
  }
}

resource "aws_iam_policy" "glue" {
  count = var.create_role && var.enable_data_format_conversion && var.data_format_conversion_glue_use_existing_role ? 1 : 0

  name   = "${local.role_name}-glue"
  path   = var.policy_path
  policy = data.aws_iam_policy_document.glue[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "glue" {
  count = var.create_role && var.enable_data_format_conversion && var.data_format_conversion_glue_use_existing_role ? 1 : 0

  role       = aws_iam_role.firehose[0].name
  policy_arn = aws_iam_policy.glue[0].arn
}

##################
# S3 Backup
##################
data "aws_iam_policy_document" "s3_backup" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources = [
      var.s3_backup_bucket_arn,
      "${var.s3_backup_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "s3_backup" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role ? 1 : 0

  name   = "${local.role_name}-s3-backup"
  path   = var.policy_path
  policy = data.aws_iam_policy_document.s3_backup[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_backup" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role ? 1 : 0

  role       = aws_iam_role.firehose[0].name
  policy_arn = aws_iam_policy.s3_backup[0].arn
}

data "aws_iam_policy_document" "s3_backup_kms" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role && var.s3_backup_kms_key_arn != null ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [
      var.s3_backup_kms_key_arn
    ]
    condition {
      test     = "StringEquals"
      values   = ["s3.${data.aws_region.current[0].name}.amazonaws.com"]
      variable = "kms:ViaService"
    }
    condition {
      test     = "StringLike"
      values   = ["${var.s3_backup_bucket_arn}/*"]
      variable = "kms:EncryptionContext:aws:s3:arn"
    }
  }
}

resource "aws_iam_policy" "s3_backup_kms" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role && var.s3_backup_kms_key_arn != null ? 1 : 0

  name   = "${local.role_name}-s3-backup-kms"
  path   = var.policy_path
  policy = data.aws_iam_policy_document.s3_backup_kms[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_backup_kms" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role && var.s3_backup_kms_key_arn != null ? 1 : 0

  role       = aws_iam_role.firehose[0].name
  policy_arn = aws_iam_policy.s3_backup_kms[0].arn
}

data "aws_iam_policy_document" "s3_backup_cw" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role && var.s3_backup_enable_log ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current[0].name}:${data.aws_caller_identity.current[0].account_id}:log-group:${local.s3_backup_cw_log_group_name}:log-stream:${local.s3_backup_cw_log_stream_name}"
    ]
  }
}

resource "aws_iam_policy" "s3_backup_cw" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role && var.s3_backup_enable_log ? 1 : 0

  name   = "${local.role_name}-s3-backup-cw"
  path   = var.policy_path
  policy = data.aws_iam_policy_document.s3_backup_cw[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_backup_cw" {
  count = var.create_role && var.enable_s3_backup && var.s3_backup_use_existing_role && var.s3_backup_enable_log ? 1 : 0

  role       = aws_iam_role.firehose[0].name
  policy_arn = aws_iam_policy.s3_backup_cw[0].arn
}