resource "aws_instance" "main" {
    # TODO: total of all counts
    count = var.active_env_provider == "aws" ? length(var.servers) : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.servers[count.index].image == "" ? var.packer_image_id : var.servers[count.index].image
    instance_type = var.servers[count.index].size

    tags = {
        Name = "${var.server_name_prefix}-${var.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}"
        Roles = join(",", var.servers[count.index].roles)
    }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = var.servers[count.index].aws_volume_size
    }

    subnet_id              = aws_subnet.public_subnet.id

    vpc_security_group_ids = compact([
        aws_security_group.default_ports.id,
        aws_security_group.ext_remote.id,

        contains(var.servers[count.index].roles, "admin") ? aws_security_group.admin_ports.id : "",
        contains(var.servers[count.index].roles, "lead") ? aws_security_group.app_ports.id : "",

        contains(var.servers[count.index].roles, "db") ? aws_security_group.db_ports.id : "",
        contains(var.servers[count.index].roles, "db") ? aws_security_group.ext_db.id : "",
    ])

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
            private_key = file(var.local_ssh_key_file)
        }
    }

    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                docker service update --constraint-add "node.hostname!=${self.tags.Name}" proxy_main
                docker service update --constraint-rm "node.hostname!=${self.tags.Name}" proxy_main
            fi

        EOF
        destination = "/tmp/dockerconstraint.sh"
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                sed -i "s|${self.private_ip}|${aws_instance.main[0].private_ip}|" /etc/nginx/conf.d/proxy.conf
                gitlab-ctl reconfigure
            fi

        EOF
        destination = "/tmp/changeip-${self.tags.Name}.sh"
        connection {
            host     = aws_instance.main[0].public_ip
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "file" {
        content = <<-EOF

            if [ "${length(regexall("lead", self.tags.Roles)) > 0}" = "true" ]; then
               docker node update --availability="drain" ${self.tags.Name}
               sleep 20;
               docker node demote ${self.tags.Name}
               sleep 5
               docker swarm leave
               docker swarm leave --force;
               exit 0
           fi
        EOF
        destination = "/tmp/remove.sh"
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }


    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.public_ip}
            exit 0;
        EOF
        on_failure = continue
    }
}



###! Run this resource when downsizing from 2 leader servers to 1 in its own apply
resource "null_resource" "cleanup" {
    count = var.active_env_provider == "aws" ? 1 : 0

    triggers = {
        should_downsize = var.downsize
    }

    #### all proxies admin   -> change nginx route ip -> safe to leave swarm
    #### dockerconstraint.sh -> changeip-NAME.sh      -> remove.sh
    #### Once docker app proxying happens on nginx instead of docker proxy app, this will be revisted

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/dockerconstraint.sh",
            var.downsize ? "/tmp/dockerconstraint.sh" : "echo 0",
        ]
        connection {
            host     = element(aws_instance.main[*].public_ip, length(aws_instance.main[*].public_ip) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/changeip-${element(aws_instance.main[*].tags.Name, length(aws_instance.main[*].tags.Name) - 1)}.sh",
            var.downsize ? "/tmp/changeip-${element(aws_instance.main[*].tags.Name, length(aws_instance.main[*].tags.Name) - 1)}.sh" : "echo 0",
        ]
        connection {
            host     = element(aws_instance.main[*].public_ip, 0)
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/remove.sh",
            var.downsize ? "/tmp/remove.sh" : "echo 0",
        ]
        connection {
            host     = element(aws_instance.main[*].public_ip, length(aws_instance.main[*].public_ip) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
}

### Some sizes for reference
# variable "aws_admin_instance_type" { default = "t3a.large" }
# variable "aws_leader_instance_type" { default = "t3a.small" }
# variable "aws_db_instance_type" { default = "t3a.micro" }
