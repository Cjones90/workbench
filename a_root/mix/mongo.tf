
module "mongo_provisioners" {
    source      = "../../provisioners"
    servers     = var.mongo_servers
    names       = var.mongo_names
    public_ips  = var.mongo_public_ips
    private_ips = var.mongo_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    deploy_key_location = var.deploy_key_location
    misc_repos      = var.misc_repos
    chef_local_dir  = var.chef_local_dir
    chef_client_ver = var.chef_client_ver

    docker_engine_version = var.docker_engine_version
    consul_version        = var.consul_version

    consul_lan_leader_ip = (length(var.admin_public_ips) > 0
        ? element(concat(var.admin_public_ips, [""]), 0)
        : element(concat(var.lead_public_ips, [""]), 0))

    role = "db_mongo"
    db_backups_enabled = var.db_backups_enabled
}


resource "null_resource" "import_mongo_db" {
    # count      = var.import_dbs && var.mongo_servers > 0 ? var.mongo_servers : 0
    count      = 0
    depends_on = [module.mongo_provisioners]

    provisioner "remote-exec" {
        inline = [
            "bash ~/import_mongo_db.sh"
        ]
        connection {
            host = element(var.mongo_public_ips, count.index)
            type = "ssh"
        }
    }
}


resource "null_resource" "change_mongo_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleing
    # would require more effort for only slightly more flexability thats not needed at the moment
    # count      = var.change_db_dns && var.mongo_servers > 0 ? var.mongo_servers : 0
    count      = 0
    depends_on = [null_resource.import_mongo_db]

    triggers = {
        update_mongo_dns = element(var.mongo_ids, var.mongo_servers - 1)
    }

    lifecycle {
        create_before_destroy = true
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.db_dns["mongo"]["dns_id"]};
                ZONE_ID=${var.db_dns["mongo"]["zone_id"]};
                URL=${var.db_dns["mongo"]["url"]};
                IP=${element(var.mongo_public_ips, var.mongo_servers - 1)};

                curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                -H "X-Auth-Email: ${var.cloudflare_email}" \
                -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                -H "Content-Type: application/json" \
                --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
            EOF
        ]
        connection {
            host = element(var.mongo_public_ips, var.mongo_servers - 1)
            type = "ssh"
        }
    }
}
