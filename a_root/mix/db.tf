
module "db_provisioners" {
    source      = "../../provisioners"
    servers     = var.db_servers
    names       = var.db_names
    public_ips  = var.db_public_ips
    private_ips = var.db_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    active_env_provider = var.active_env_provider
    root_domain_name = var.root_domain_name
    deploy_key_location = var.deploy_key_location
    chef_local_dir  = var.chef_local_dir
    chef_client_ver = var.chef_client_ver

    docker_engine_install_url = var.docker_engine_install_url
    consul_version        = var.consul_version

    consul_lan_leader_ip = (length(var.admin_public_ips) > 0
        ? element(concat(var.admin_public_ips, [""]), var.admin_servers - 1)
        : element(concat(var.lead_public_ips, [""]), 0))

    role = "db"
    db_backups_enabled = var.db_backups_enabled
    pg_read_only_pw = var.pg_read_only_pw

    # Variable to ensure the cookbooks are uploaded before bootstrapping
    chef_server_ready = local.chef_server_ready
}

resource "null_resource" "change_db_hostname" {
    count      = var.db_servers

    provisioner "remote-exec" {
        inline = [
            "sudo hostnamectl set-hostname ${var.root_domain_name}",
            "sed -i 's/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 ${var.root_domain_name} ${element(var.db_names, count.index)}/' /etc/hosts",
            "sed -i '$ a 127.0.1.1 ${var.root_domain_name} ${element(var.db_names, count.index)}' /etc/hosts",
            "sed -i '$ a ${element(var.db_public_ips, count.index)} ${var.root_domain_name} ${var.root_domain_name}' /etc/hosts",
            "cat /etc/hosts"
        ]
        connection {
            host = element(var.db_public_ips, count.index)
            type = "ssh"
        }
    }
}

resource "null_resource" "cron_db" {
    count      = var.db_servers > 0 ? var.db_servers : 0
    depends_on = [module.db_provisioners]

    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/code/cron" ]
    }

    triggers = {
        num_dbs = length(var.dbs_to_import)
    }

    provisioner "file" {
        # TODO: aws_bucket_name and region based off imported db's options
        # TODO: Support multiple dbs for same type of db
        content = fileexists("${path.module}/template_files/cron/db.tmpl") ? templatefile("${path.module}/template_files/cron/db.tmpl", {
            aws_bucket_region = var.aws_bucket_region
            aws_bucket_name = var.aws_bucket_name
            redis_db = length(local.redis_dbs) > 0 ? local.redis_dbs[0] : ""
            mongo_db = length(local.mongo_dbs) > 0 ? local.mongo_dbs[0] : ""
            pg_db = length(local.pg_dbs) > 0 ? local.pg_dbs[0] : ""
            pg_fn = length(local.pg_fn) > 0 ? local.pg_fn["pg"] : "" # TODO: hack
        }) : ""
        destination = "/root/code/cron/db.cron"
    }

    provisioner "remote-exec" {
        inline = [ "crontab /root/code/cron/db.cron", "crontab -l" ]
    }

    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "provision_db_files" {
    count      = var.import_dbs && var.db_servers > 0 ? var.db_servers : 0
    depends_on = [module.db_provisioners]

    provisioner "file" {
        content = file("${path.module}/template_files/import_mongo_db.sh")
        destination = "~/import_mongo_db.sh"
    }
    provisioner "file" {
        content = file("${path.module}/template_files/import_pg_db.sh")
        destination = "~/import_pg_db.sh"
    }
    provisioner "file" {
        content = file("${path.module}/template_files/import_redis_db.sh")
        destination = "~/import_redis_db.sh"
    }
    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "import_dbs" {
    depends_on = [null_resource.provision_db_files]
    count = var.import_dbs && var.db_servers > 0 && length(var.dbs_to_import) > 0 ? length(var.dbs_to_import) : 0

    provisioner "file" {
        content = <<-EOF
            IMPORT=${var.dbs_to_import[count.index]["import"]};
            DB_TYPE=${var.dbs_to_import[count.index]["type"]};
            AWS_BUCKET_NAME=${var.dbs_to_import[count.index]["aws_bucket"]};
            AWS_BUCKET_REGION=${var.dbs_to_import[count.index]["aws_region"]};
            DB_NAME=${var.dbs_to_import[count.index]["dbname"]};

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "mongo" ]; then
                bash ~/import_mongo_db.sh -r $AWS_BUCKET_REGION -b $AWS_BUCKET_NAME -d $DB_NAME;
            fi

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "pg" ]; then
                bash ~/import_pg_db.sh -r $AWS_BUCKET_REGION -b $AWS_BUCKET_NAME -d $DB_NAME;
            fi

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "redis" ]; then
                bash ~/import_redis_db.sh -r $AWS_BUCKET_REGION -b $AWS_BUCKET_NAME -d $DB_NAME;
            fi
        EOF
        destination = "/tmp/import_dbs.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/import_dbs.sh",
            "/tmp/import_dbs.sh",
        ]
    }

    connection {
        # TODO: Determine how to handle multiple db servers
        host = element(var.db_public_ips, 0)
        type = "ssh"
    }
}

resource "null_resource" "change_db_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleting/modifying
    # would require more effort for only slightly more flexability thats not needed at the moment
    count = var.change_db_dns && var.db_servers > 0 ? length(keys(var.db_dns)) : 0
    depends_on = [
        null_resource.import_dbs,
    ]

    triggers = {
        update_db_dns = element(var.db_ids, var.db_servers - 1)
    }

    lifecycle {
        create_before_destroy = true
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.db_dns[element(keys(var.db_dns), count.index)]["dns_id"]};
                ZONE_ID=${var.db_dns[element(keys(var.db_dns), count.index)]["zone_id"]};
                URL=${var.db_dns[element(keys(var.db_dns), count.index)]["url"]};
                IP=${element(var.db_public_ips, var.db_servers - 1)};

                # curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                # -H "X-Auth-Email: ${var.cloudflare_email}" \
                # -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                # -H "Content-Type: application/json" \
                # --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
            EOF
        ]
        connection {
            host = element(var.db_public_ips, var.db_servers - 1)
            type = "ssh"
        }
    }
}

resource "null_resource" "sync_db_with_admin_firewall" {
    count      = var.admin_servers
    depends_on = [null_resource.change_db_dns]


    provisioner "file" {
        content = <<-EOF
            check_consul() {

                chef-client;
                consul kv put db_bootstrapped true;

                ADMIN_READY=$(consul kv get admin_ready);

                if [ "$ADMIN_READY" = "true" ]; then
                    echo "Firewalls ready: DB"
                    exit 0;
                else
                    echo "Waiting 60 for admin firewall";
                    sleep 60;
                    check_consul
                fi
            }

            check_consul
        EOF
        destination = "/tmp/sync_db_firewall.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/sync_db_firewall.sh",
            "/tmp/sync_db_firewall.sh",
        ]
    }

    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}
