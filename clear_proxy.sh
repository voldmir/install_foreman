#!/usr/bin/env bash

# Clear smart installations
systemctl stop smart-proxy 
systemctl stop smart-proxy-dynflow-core 
systemctl stop puppet 
systemctl stop puppetserver

apt-get remove puppetserver -y
apt-get remove puppet -y
apt-get remove ruby libruby -y

userdel -fr smartforeman
userdel -fr _smartforeman
userdel -fr puppet
userdel -fr _puppet
userdel -fr _dynflow
userdel -fr postgres
groupdel -f smartforeman
groupdel -f _smartforeman
groupdel -f puppet
groupdel -f _puppet
groupdel -f _dynflow
groupdel -f dynflow
groupdel -f postgres
groupdel -f _postgres

rm -fr /opt/{ruby}
rm -fr /var/lib/{pgsql,puppetserver,smart-proxy,smart-proxy-dynflow-core}
rm -fr /var/run/{pgsql,puppetserver,smart-proxy,smart-proxy-dynflow-core}
rm -fr /etc/{smart-proxy,puppet}
rm -f /lib/systemd/system/{smart-proxy.service,smart-proxy-dynflow-core.service}
rm -fr /var/log/{puppet,puppetserver,smart-proxy}
rm -fr /opt/puppet
rm -fr /usr/lib/puppet-modules
rm -fr /usr/lib/ruby
rm -f /etc/tmpfiles.d/tmpfiles-foreman-smart-proxy.conf
rm -fr /etc/smart_proxy_dynflow_core

systemctl daemon-reload
