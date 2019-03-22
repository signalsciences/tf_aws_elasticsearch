/*
Add a new set of data.aws_iam_policy_document, aws_elasticsearch_domain, aws_elasticsearch_domain_policy, because currently terraform/aws_elasticsearch_domain does not handle properly null/empty "vpc_options"
*/

/*Need to use interpolation for output variables until issue #15605 is solved */

locals {
  es_arn       = "${length(var.vpc_options["subnet_ids"]) > 0 ? element(concat(aws_elasticsearch_domain.es_vpc.*.arn,list("")),0) : element(concat(aws_elasticsearch_domain.es.*.arn,list("")),0)}"
  es_endpoint  = "${length(var.vpc_options["subnet_ids"]) > 0 ? element(concat(aws_elasticsearch_domain.es_vpc.*.endpoint,list("")),0) : element(concat(aws_elasticsearch_domain.es.*.endpoint,list("")),0)}"
  es_domain_id = "${length(var.vpc_options["subnet_ids"]) > 0 ? element(concat(aws_elasticsearch_domain.es_vpc.*.domain_id,list("")),0) : element(concat(aws_elasticsearch_domain.es.*.domain_id,list("")),0)}"
}

data "aws_iam_policy_document" "es_vpc_management_access" {
  count = "${length(var.vpc_options["subnet_ids"]) > 0 ? 1 : 0}"

  statement {
    actions = [
      "es:ESHttpGet",
      "es:ESHttpHead",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      "${aws_elasticsearch_domain.es_vpc.arn}",
      "${aws_elasticsearch_domain.es_vpc.arn}/*",
    ]

    principals {
      type = "AWS"

      identifiers = ["${distinct(compact(var.management_iam_roles))}"]
    }
  }

  statement {
    actions = [
      "es:ESHttpDelete"
    ]

    resources = ["*"]

    principals {
      type = "AWS"

      identifiers = ["${distinct(compact(var.super_management_iam_roles))}"]
    }
  }

  statement {
    actions = [
      "es:ESHttpDelete",
    ]

    resources = [ "${formatlist("${aws_elasticsearch_domain.es_vpc.arn}/%s-*/*/*", var.deny_del_indices_prefixes)}" ]

    principals {
      type = "AWS"

      identifiers = ["${distinct(compact(var.management_iam_roles))}"]
    }
  }
}

resource "aws_elasticsearch_domain" "es_vpc" {
  count                 = "${length(var.vpc_options["subnet_ids"]) > 0 ? 1 : 0}"
  domain_name           = "${local.domain_name}"
  elasticsearch_version = "${var.es_version}"
  depends_on            = ["aws_cloudwatch_log_resource_policy.elasticsearch-log-publishing-policy"]

  encrypt_at_rest = {
    enabled    = "${var.encrypt_at_rest}"
    kms_key_id = "${var.kms_key_id}"
  }

  node_to_node_encryption {
    enabled = "${var.node_to_node_encryption}"
  }

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

  vpc_options = ["${var.vpc_options}"]
  ebs_options {
    ebs_enabled = "${var.ebs_volume_size > 0 ? true : false}"
    volume_size = "${var.ebs_volume_size}"
    volume_type = "${var.ebs_volume_type}"
  }
  snapshot_options {
    automated_snapshot_start_hour = "${var.snapshot_start_hour}"
  }
  tags = "${merge(var.tags, map(
    "Domain", "${var.domain_name}"
  ))}"
}

resource "aws_elasticsearch_domain_policy" "es_vpc_management_access" {
  count           = "${length(var.vpc_options["subnet_ids"]) > 0 ? 1 : 0}"
  domain_name     = "${local.domain_name}"
  access_policies = "${data.aws_iam_policy_document.es_vpc_management_access.json}"
}
