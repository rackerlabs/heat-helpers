#!/bin/bash

# Exit script if any command fails
set -e
set -o pipefail

# Create directories and setup log
mkdir -p /etc/chef /var/log/chef &>/dev/null
LOGFILE='/var/log/chef/bootstrap.log'

# Initial timestamp and debug information
date > $LOGFILE
echo 'Starting cloud-init bootstrap' >> $LOGFILE
echo 'chef_environment parameter: %chef_environment%' >> $LOGFILE
echo 'role parameter: %role%' >> $LOGFILE
echo 'chef_organization parameter: %chef_organization%' >> $LOGFILE
echo 'chef_version parameter: %chef_version%' >> $LOGFILE

# Create the encrypted data bag key file (optional)
CHEFDATABAGSECRET='%chef_encrypted_data_bag_secret%'
if [ -z $CHEFDATABAGSECRET ]; then
  echo 'chef_encrypted_data_bag_secret parameter: not passed' >> $LOGFILE
else
  echo 'Storing encrypted data bag key in /etc/chef/encrypted_data_bag_secret' >> $LOGFILE
  touch /etc/chef/encrypted_data_bag_secret
  cat >/etc/chef/encrypted_data_bag_secret <<EOF
%chef_encrypted_data_bag_secret%
EOF
fi

# Store the validation key in /etc/chef/validation.pem
echo 'Storing validation key in /etc/chef/validation.pem' >> $LOGFILE
touch /etc/chef/validation.pem
cat >/etc/chef/validation.pem <<EOF
%chef_validator%
EOF

# Infer the Chef Server's URL if none was passed
CHEFSERVERURL='%chef_server_url%'
if [ -z $CHEFSERVERURL ]; then
  echo 'chef_server_url parameter: not passed' >> $LOGFILE
  CHEFSERVERURL='https://api.opscode.com/organizations/%chef_organization%'
else
  echo "chef_server_url parameter: $CHEFSERVERURL" >> $LOGFILE
  CHEFSERVERURL='%chef_server_url%'
fi

# Cook a minimal client.rb for getting the chef-client registered
echo 'Creating a minimal /etc/chef/client.rb' >> $LOGFILE
touch /etc/chef/client.rb
cat >/etc/chef/client.rb <<EOF
log_level        :info
log_location     STDOUT
chef_server_url  "$CHEFSERVERURL"
chef_validator         "/etc/chef/validation.pem"
validation_client_name "%chef_organization%-validator"
EOF

# Cook the first boot file
echo 'Creating a minimal /etc/chef/first-boot.json' >> $LOGFILE
touch /etc/chef/first-boot.json
CHEF_RUN_LIST='%runlist%'
if [ -z $CHEF_RUN_LIST ]; then
  echo 'runlist parameter: not passed' >> $LOGFILE
  cat >/etc/chef/first-boot.json <<EOF
{ "run_list":["role[%role%]"] }
EOF
else
  echo "runlist parameter: $CHEF_RUN_LIST" >> $LOGFILE
  cat >/etc/chef/first-boot.json <<EOF
{ "run_list":[$CHEF_RUN_LIST] }
EOF
fi

# Install chef-client through omnibus (if not already available)
if [ ! -f /usr/bin/chef-client ]; then
  echo 'Installing chef using omnibus installer' >> $LOGFILE
  curl -L https://www.opscode.com/chef/install.sh | bash -s -- -v '%chef_version%' >>$LOGFILE 2>&1
fi

# Kick off the first chef run (5 attempts)
if [ -f /usr/bin/chef-client ]; then
  ATTEMPT=0
  until [ $ATTEMPT -ge 5 ]
  do
    echo "First chef-client run. Attempt $ATTEMPT of 5. See /var/log/chef/first-boot.log" >> $LOGFILE
    /usr/bin/chef-client -E %chef_environment% -j /etc/chef/first-boot.json -l info -L /var/log/chef/first-boot.log && break
    ATTEMPT=$[$ATTEMPT+1]
    sleep 5
  done
fi

# Script complete. Log final timestamp
date >> $LOGFILE
