#!/bin/bash
#
# Small script that bootstraps a Chef node.
# I wrote this, as net-ssh still has problems with decent ssh ciphers
#
# Usage:
# ./ubuntu14.04-gems-ssh.sh chef_nodename [fqdn|ip]

# Fail on uninitialized variables or if something goes wrong
set -o nounset
set -o errexit

# Load configuration
. config.sh

# SSH base command
SSH_CMD="ssh $2"

# Update system
$SSH_CMD "sudo apt-get update"
$SSH_CMD "sudo apt-get dist-upgrade -y"

# Check whether chef package is installed
if $SSH_CMD "dpkg --list |grep chef" |grep -q '^ii'; then
  echo "Chef package already installed, skipping"
else
  echo "Installing Chef package"
  $SSH_CMD "sudo apt-get install wget -y"
  $SSH_CMD "wget $CHEF_CLIENT_PACKAGE"
  $SSH_CMD "sudo dpkg -i $(basename $CHEF_CLIENT_PACKAGE)"
fi

$SSH_CMD "sudo mkdir -p /etc/chef /var/log/chef"

# Copy validation key
$SSH_CMD "awk NF |sudo tee /etc/chef/validation.pem" < ../.chef/$ORGANIZATION.pem
$SSH_CMD "sudo chmod 0600 /etc/chef/validation.pem"

# Create client configuration
$SSH_CMD "cat |sudo tee /etc/chef/client.rb" <<EOP
chef_server_url '$CHEF_SERVER'
validation_client_name '$ORGANIZATION-validator'
client_fork true
log_location '/var/log/chef/client.log'
interval 900
ssl_ca_path '/etc/ssl/certs'
ssl_verify_mode :$SSL_VERIFY_MODE
node_name '$1'

Dir.glob(File.join('/etc/chef', 'client.d', '*.rb')).each do |conf|
  Chef::Config.from_file(conf)
end
EOP

# Register node at the Chef server
$SSH_CMD "sudo chef-client --once"
