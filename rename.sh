#!/bin/bash
#
# Small script that renames a Chef node.
#
# Usage:
# ./rename.sh old_name new_name [fqdn|ip]

# Fail on uninitialized variables or if something goes wrong
set -o nounset
set -o errexit

# Load configuration
. config.sh

# SSH base command
SSH_CMD="ssh $2.$DOMAIN"

# Copy node
tempfile=$(mktemp XXX.json)
echo "Copyng $1 to $2"
knife node show -F json $1 |sed "s/$1/$2/" > $tempfile
cat $tempfile
knife node from file $tempfile
rm $tempfile

# Remove old node configuration
$SSH_CMD "sudo rm /etc/chef/client.{rb,pem}"

# Copy validation key
$SSH_CMD "awk NF |sudo tee /etc/chef/validation.pem" < ../.chef/chef-validator.pem
$SSH_CMD "sudo chmod 0600 /etc/chef/validation.pem"


# Create client configuration
$SSH_CMD "cat |sudo tee /etc/chef/client.rb" <<EOP
chef_server_url '$CHEF_SERVER'
validation_client_name 'chef-validator'
client_fork true
log_location '/var/log/chef/client.log'
interval 900
ssl_ca_path '/etc/ssl/certs'
node_name '$2'

Dir.glob(File.join('/etc/chef', 'client.d', '*.rb')).each do |conf|
  Chef::Config.from_file(conf)
end
EOP

# Remove old node/client
knife node delete -y $1
knife client delete -y $1

# Register node at the Chef server
$SSH_CMD "sudo chef-client --once"
