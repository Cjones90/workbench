data "aws_route53_zone" "default" {
    name         = var.root_domain_name
}

# Based on app, create .db, .dev, and .dev.db subdomains (not used just yet)
# TODO: See if we can do locals like this in an envs/vars.tf file with a just declared variable
locals {
    cname_aliases = [
        for app in var.app_definitions:
        [app.subdomain_name, format("${app.subdomain_name}.db"), format("${app.subdomain_name}.dev"), format("${app.subdomain_name}.dev.db")]
        if app.create_subdomain == "true"
    ]
}

resource "aws_route53_record" "default_cname" {
    count           = var.dns_provider == "aws_route53" ? length(compact(flatten(local.cname_aliases))) : 0
    name            = compact(flatten(local.cname_aliases))[count.index]
    zone_id         = data.aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ var.root_domain_name ]
}

resource "aws_route53_record" "default_a_admin" {
    count           = var.dns_provider == "aws_route53" ? length(compact(var.admin_arecord_aliases)) : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = compact(var.admin_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    # TODO: Check how we support tags changing while deployed as we have each aws_instance
    #  lifecycle attr set to     ignore_changes= [ tags ]
    records = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("admin", SERVER.tags.Roles)) > 0
    ]
}

resource "aws_route53_record" "default_a_db" {
    count           = var.dns_provider == "aws_route53" ? length(compact(var.db_arecord_aliases)) : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = compact(var.db_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("db", SERVER.tags.Roles)) > 0
    ]
}

resource "aws_route53_record" "default_a_leader" {
    count           = var.dns_provider == "aws_route53" ? length(compact(var.leader_arecord_aliases)) : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = compact(var.leader_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("lead", SERVER.tags.Roles)) > 0
    ]
}

resource "aws_route53_record" "default_a_leader_root" {
    count           = var.dns_provider == "aws_route53" ? 1 : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = var.root_domain_name
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("lead", SERVER.tags.Roles)) > 0
    ]
}