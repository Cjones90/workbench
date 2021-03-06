#!/bin/bash

MONGO_VERSION="4.2.7"
BIND_IP="0.0.0.0"

while getopts "v:i:b" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BACKUP=true;;
        i) BIND_IP=$OPTARG;;
        v) MONGO_VERSION=$OPTARG;;
    esac
done

MONGO_MAJOR_MINOR=${MONGO_VERSION%%.[0-9]}

# TODO: Detect proper version and IP input


### Backup and shutdown old for upgrade
if [ "$BACKUP" = true ]; then
    # backup all of mongo before
    # TODO: Check that mongo is up before attempting to dump
    bash /root/code/scripts/db/dumpmongo.sh

    # Chose one based on version
    # TODO: Auto detect which is supported
    # sudo service mongod stop
    sudo systemctl stop mongod
fi


sudo apt-get install gnupg;
wget -qO - https://www.mongodb.org/static/pgp/server-$MONGO_MAJOR_MINOR.asc | sudo apt-key add -

echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/$MONGO_MAJOR_MINOR multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-$MONGO_MAJOR_MINOR.list

sudo apt-get update

sudo apt-get install -y mongodb-org=$MONGO_VERSION mongodb-org-server=$MONGO_VERSION mongodb-org-shell=$MONGO_VERSION mongodb-org-mongos=$MONGO_VERSION mongodb-org-tools=$MONGO_VERSION

sed -i "s|bindIp: 0.0.0.0|bindIp: $BIND_IP|" /etc/mongod.conf;
sed -i "s|bindIp: 127.0.0.1|bindIp: $BIND_IP|" /etc/mongod.conf;


sudo systemctl daemon-reload;
sudo systemctl start mongod;
sudo systemctl enable mongod;

## To purge
#### sudo service mongod stop
#### sudo apt-get purge mongodb-org*
#### sudo rm -r /var/log/mongodb
#### sudo rm -r /var/lib/mongodb
