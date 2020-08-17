#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit
IFS=$'\n\t'

TEMPLATE_DIR=${TEMPLATE_DIR:-/tmp/haproxy}

################################################################################
### Packages ###################################################################
################################################################################

# Update the OS to begin with to catch up to the latest packages.
sudo yum update -y

# Install necessary packages
sudo yum install -y make gcc perl pcre-devel zlib-devel systemd-devel openssl-devel tar


################################################################################
### HAProxy ####################################################################
################################################################################

# Download/Extract source
curl -L http://www.haproxy.org/download/1.9/src/haproxy-1.9.8.tar.gz | tar xz -C /tmp
cd /tmp/haproxy-*

# Compile HAProxy
# https://github.com/haproxy/haproxy/blob/master/README

make -j 4 TARGET=linux2628 USE_NS=1 USE_TFO=1 USE_OPENSSL=1 USE_ZLIB=1 USE_PCRE=1 USE_SYSTEMD=1

sudo make install


# Move haproxy config to correct place
sudo mkdir -p /etc/haproxy/
sudo mkdir -p /var/lib/haproxy
sudo cp "$TEMPLATE_DIR/haproxy.cfg" /etc/haproxy/haproxy.cfg

# Create a service account for the exporter to use
sudo useradd --no-create-home --shell /sbin/nologin haproxy
sudo chown -R haproxy:haproxy /var/lib/haproxy

#Set up logging
sudo mv "$TEMPLATE_DIR"/rsyslog.d/haproxy.conf /etc/rsyslog.d/haproxy.conf

# Make sure HAProxy starts on boot.
sudo mv "$TEMPLATE_DIR"/haproxy.service /usr/lib/systemd/system/haproxy.service
sudo systemctl daemon-reload
sudo systemctl enable haproxy.service

################################################################################
### HAProxy prometheus exporter ################################################
################################################################################
# TODO install haproxy prometheus exporter
EXPORTER_BASE_DIR="/opt/haproxy_exporter"
sudo mkdir -p $EXPORTER_BASE_DIR
curl -L https://github.com/prometheus/haproxy_exporter/releases/download/v0.10.0/haproxy_exporter-0.10.0.linux-amd64.tar.gz | sudo tar xz --strip 1 -C $EXPORTER_BASE_DIR

# Create a service account for the exporter to use
sudo useradd --no-create-home --shell /sbin/nologin haproxy_exporter
sudo chown -R haproxy_exporter:haproxy_exporter $EXPORTER_BASE_DIR

# Install the exporter service
sudo mv "$TEMPLATE_DIR"/haproxy_exporter.service /usr/lib/systemd/system/haproxy_exporter.service
sudo systemctl daemon-reload
sudo systemctl enable haproxy_exporter


#####################################################################
### Amazon CloudWatch Agent #########################################
#####################################################################
sudo yum install -y https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo cp "$TEMPLATE_DIR/cloudwatch-agent-config.json" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo systemctl daemon-reload
sudo systemctl enable amazon-cloudwatch-agent


#####################################################################
### Amazon SSM Agent ################################################
#####################################################################
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl daemon-reload
sudo systemctl enable amazon-ssm-agent


# Make sure Amazon Time Sync Service starts on boot.
sudo chkconfig chronyd on

# Make sure that chronyd syncs RTC clock to the kernel.
cat <<EOF | sudo tee -a /etc/chrony.conf
# This directive enables kernel synchronisation (every 11 minutes) of the
# real-time clock. Note that it can’t be used along with the 'rtcfile' directive.
rtcsync
EOF


################################################################################
### Prometheus Node exporter ###################################################
################################################################################
sudo curl -Lo /etc/yum.repos.d/_copr_ibotty-prometheus-exporters.repo \
    https://copr.fedorainfracloud.org/coprs/ibotty/prometheus-exporters/repo/epel-7/ibotty-prometheus-exporters-epel-7.repo
sudo yum install -y node_exporter
sudo systemctl enable node_exporter.service
sudo systemctl start node_exporter.service


################################################################################
### Cleanup ####################################################################
################################################################################

# Clean up yum caches to reduce the image size
sudo yum clean all
sudo rm -rf \
    $TEMPLATE_DIR  \
    /var/cache/yum

# Clean up files to reduce confusion during debug
sudo rm -rf \
    /etc/hostname \
    /etc/machine-id \
    /etc/resolv.conf \
    /etc/ssh/ssh_host* \
    /home/ec2-user/.ssh/authorized_keys \
    /root/.ssh/authorized_keys \
    /var/lib/cloud/data \
    /var/lib/cloud/instance \
    /var/lib/cloud/instances \
    /var/lib/cloud/sem \
    /var/lib/dhclient/* \
    /var/lib/dhcp/dhclient.* \
    /var/lib/yum/history \
    /var/log/cloud-init-output.log \
    /var/log/cloud-init.log \
    /var/log/secure \
    /var/log/wtmp

sudo touch /etc/machine-id
