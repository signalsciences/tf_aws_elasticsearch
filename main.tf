locals = {
  log_groups = ["${var.index_slow_log_cloudwatch_log_group}", "${var.search_slow_log_cloudwatch_log_group}", "${var.es_app_log_cloudwatch_log_group}"]
}

# Elasticsearch domain
data "aws_iam_policy_document" "es_management_access" {
  count = "${length(var.vpc_options["subnet_ids"]) > 0 ? 0 : 1}"

  statement {
    actions = [
      "es:ESHttpGet",
      "es:ESHttpHead",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      "${aws_elasticsearch_domain.es.arn}",
      "${aws_elasticsearch_domain.es.arn}/*",
    ]

    principals {
      type = "AWS"

      identifiers = ["${distinct(compact(var.management_iam_roles))}"]
    }

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"

      values = ["${distinct(compact(var.management_public_ip_addresses))}"]
    }
  }
  statement {
    actions = [
      "es:ESHttpDelete",
    ]

    resources = [ "${formatlist("${aws_elasticsearch_domain.es.arn}/%s-*/*/*", var.deny_del_indices_prefixes)}" ]

    principals {
      type = "AWS"

      identifiers = ["${distinct(compact(var.management_iam_roles))}"]
    }

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"

      values = ["${distinct(compact(var.management_public_ip_addresses))}"]
    }
  }
}

resource "aws_cloudwatch_log_group" "index_slow_log" {
  name = "${var.index_slow_log_cloudwatch_log_group}"
}
resource "aws_cloudwatch_log_group" "search_slow_log" {
  name = "${var.search_slow_log_cloudwatch_log_group}"
}

resource "aws_cloudwatch_log_group" "es_app_log" {
  name = "${var.es_app_log_cloudwatch_log_group}"
}

data "aws_iam_policy_document" "elasticsearch-log-publishing-policy" {
  count           = "${(var.index_slow_log_enabled || var.search_slow_log_enabled || var.es_app_log_enable) ? 1 : 0}"
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
    ]

    resources = [ "arn:aws:logs:*" ]

    principals {
      identifiers = ["es.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "elasticsearch-log-publishing-policy" {
  count           = "${(var.index_slow_log_enabled || var.search_slow_log_enabled || var.es_app_log_enable) ? 1 : 0}"
  policy_document = "${data.aws_iam_policy_document.elasticsearch-log-publishing-policy.json}"
  policy_name     = "elasticsearch-log-publishing-policy-${local.domain_name}"
}

resource "aws_elasticsearch_domain" "es" {
  count                 = "${length(var.vpc_options["subnet_ids"]) > 0 ? 0 : 1}"
  domain_name           = "${local.domain_name}"
  elasticsearch_version = "${var.es_version}"
  depends_on            = ["aws_cloudwatch_log_resource_policy.elasticsearch-log-publishing-policy"]

  log_publishing_options = [{
      log_type                 = "INDEX_SLOW_LOGS"
      cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.index_slow_log.arn}"
      enabled                  = "${var.index_slow_log_enabled}"
    }, {
      log_type                 = "SEARCH_SLOW_LOGS"
      cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.search_slow_log.arn}"
      enabled                  = "${var.search_slow_log_enabled}"
    }, {
      log_type                 = "ES_APPLICATION_LOGS"
      cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.es_app_log.arn}"
      enabled                  = "${var.es_app_log_enable}"
    }
  ]

  cluster_config {
    instance_type            = "${var.instance_type}"
    instance_count           = "${var.instance_count}"
    dedicated_master_enabled = "${var.instance_count >= var.dedicated_master_threshold ? true : false}"
    dedicated_master_count   = "${var.instance_count >= var.dedicated_master_threshold ? 3 : 0}"
    dedicated_master_type    = "${var.instance_count >= var.dedicated_master_threshold ? (var.dedicated_master_type != "false" ? var.dedicated_master_type : var.instance_type) : ""}"
    zone_awareness_enabled   = "${var.es_zone_awareness}"
  }

  # advanced_options {
  # }

  ebs_options {
    ebs_enabled = "${var.ebs_volume_size > 0 ? true : false}"
    volume_size = "${var.ebs_volume_size}"
    volume_type = "${var.ebs_volume_type}"
  }
  snapshot_options {
    automated_snapshot_start_hour = "${var.snapshot_start_hour}"
  }
  tags = "${merge(var.tags, map(
    "Domain", "${local.domain_name}"
  ))}"
}

resource "aws_elasticsearch_domain_policy" "es_management_access" {
  count           =  "${length(var.vpc_options["subnet_ids"]) > 0 ? 0 : 1}"
  domain_name     = "${local.domain_name}"
  access_policies = "${data.aws_iam_policy_document.es_management_access.json}"
}

