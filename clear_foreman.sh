#!/usr/bin/env bash

# Clear foreman installations
systemctl stop postgresql 
systemctl stop foreman 
systemctl stop smart-proxy 
systemctl stop smart-proxy-dynflow-core 
systemctl stop puppet 
systemctl stop puppetserver

apt-get remove puppetserver -y
apt-get remove puppet -y
apt-get remove ruby libruby -y
apt-get remove postgresql16-server -y
apt-get remove postgresql16 -y
apt-get remove postgresql-common -y
apt-get remove foreman -y
apt-get remove node-sass -y
apt-get remove node -y

userdel -fr smartforeman
userdel -fr _smartforeman
userdel -fr foreman
userdel -fr _foreman
userdel -fr puppet
userdel -fr _puppet
userdel -fr _dynflow
userdel -fr postgres
groupdel -f smartforeman
groupdel -f _smartforeman
groupdel -f foreman
groupdel -f _foreman
groupdel -f puppet
groupdel -f _puppet
groupdel -f _dynflow
groupdel -f dynflow
groupdel -f postgres
groupdel -f _postgres

rm -fr /opt/{foreman,ruby}
rm -fr /var/lib/{pgsql,puppetserver,smart-proxy,foreman,smart-proxy-dynflow-core}
rm -fr /var/run/{pgsql,puppetserver,smart-proxy,foreman,smart-proxy-dynflow-core}
rm -fr /etc/{smart-proxy,foreman,puppet}
rm -f /etc/sysconfig/{foreman,foreman-jobs}
rm -f /etc/cron.d/foreman
rm -fr /var/cache/foreman
rm -fr /var/www/foreman
rm -f /lib/systemd/system/{foreman.service,foreman-jobs.service,smart-proxy.service,smart-proxy-dynflow-core.service}
rm -f /etc/logrotate.d/foreman
rm -fr /var/log/{foreman,puppet,puppetserver,smart-proxy}
rm -fr /var/spool/foreman
rm -fr /opt/puppet
rm -fr /usr/lib/puppet-modules
rm -fr /usr/lib/ruby
rm -f /etc/tmpfiles.d/tmpfiles-foreman-smart-proxy.conf
rm -fr /etc/smart_proxy_dynflow_core

systemctl daemon-reload
