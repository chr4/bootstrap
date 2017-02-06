#!/bin/bash
#
# Small script that bootstraps a Chef node.
# I wrote this, as net-ssh still has problems with decent ssh ciphers
#
# Usage:
# ./ubuntu14.04-gems-ssh.sh nodename fqdn|ip [environment] [run_list]

# Fail on uninitialized variables or if something goes wrong
set -o nounset
set -o errexit

# Arguments
NODE=$1
shift
HOST=$1
shift
ENVIRONMENT=$1
shift
RUN_LIST=$@

# Load configuration
. config.sh

# SSH base command
SSH_CMD="ssh $HOST"

# Use apt-cacher, if APT_PROXY is set
if [ -n "$APT_PROXY" ]; then
  $SSH_CMD "cat |sudo tee /etc/apt/apt.conf.d/01proxy" <<EOP
Acquire::http::Proxy "$APT_PROXY";
Acquire::https::Proxy "DIRECT";
EOP
fi

# Update system
$SSH_CMD "sudo apt-get update"
$SSH_CMD "sudo apt-get dist-upgrade -y"

# Check whether chef package is installed and in the required version
INSTALLED_CHEF_VERSION=$($SSH_CMD "dpkg --list |grep chef |grep '^ii' |awk '{print \$3}'")
if [ "$CHEF_VERSION" == "$INSTALLED_CHEF_VERSION" ]; then
  echo "Chef package ($CHEF_VERSION) already installed, skipping"
else
  echo "Installing Chef package ($CHEF_VERSION)"
  $SSH_CMD "sudo apt-get install wget -y"
  $SSH_CMD "wget $CHEF_CLIENT_PACKAGE"

  # Verify SHA256 checksum
  SHA256SUM=$($SSH_CMD sha256sum $(basename $CHEF_CLIENT_PACKAGE) |cut -f1 -d' ')
  if [ "$SHA256SUM" != "$CHEF_CLIENT_SHA256" ]; then
    echo "SHA256SUM of $(basename $CHEF_CLIENT_PACKAGE) invalid."
    exit 1
  fi

  # Install chef-client package
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
node_name '$NODE'

Dir.glob(File.join('/etc/chef', 'client.d', '*.rb')).each do |conf|
  Chef::Config.from_file(conf)
end
EOP

# Register node at the Chef server
$SSH_CMD "sudo chef-client --once"

# Set the environment if given
if [ -n "$ENVIRONMENT" ]; then
  echo "Setting environment to $ENVIRONMENT"
  knife node environment set $NODE $ENVIRONMENT
fi

# Set run_list if given
if [ -n "$RUN_LIST" ]; then
  echo "Adding items to run_list: $RUN_LIST"
  knife node run_list set $NODE $RUN_LIST
fi

# Add additional packages
if [ -n "$APT_PACKAGES" ]; then
  $SSH_CMD "sudo apt-get install $APT_PACKAGES -y"
fi
