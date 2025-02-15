#!/usr/bin/env bash

store="https://github.com/voldmir/install_foreman/releases/download/v1.0.3"

apt-get update

apt-get install java-21-openjdk -y
apt-get install puppetserver puppet -y
echo -e "\nSetup puppet"


cat << EOF > /etc/puppet/puppet.conf
[main]
    basemodulepath = /etc/puppet/code/environments/common:/etc/puppet/code/modules:/opt/puppet/puppet/modules:/usr/share/puppet/modules
    codedir = /etc/puppet/code
    environmentpath = /etc/puppet/code/environments
    hiera_config = \$confdir/hiera.yaml
    hostprivkey = \$privatekeydir/\$certname.pem { mode = 640 }
    logdir = /var/log/puppet
    pluginfactsource = puppet:///pluginfacts
    pluginsource = puppet:///plugins
    privatekeydir = \$ssldir/private_keys { group = service }
    reports = foreman
    rundir = /var/run/puppet
    server = $(hostname -f)
    show_diff = true
    ssldir = /etc/puppet/ssl
    vardir = /opt/puppet/cache
[agent]
    classfile = \$statedir/classes.txt
    default_schedules = false
    environment = production
    listen = false
    localconfig = \$vardir/localconfig
    masterport = 8140
    noop = false
    report = true
    runinterval = 1800
    splay = false
    splaylimit = 1800
    usecacheonfailure = true
    server = $(hostname -f)
[master]
    autosign = /etc/puppet/autosign.conf { mode = 0664 }
    ca = true
    certname = $(hostname -f)
    logdir = /var/log/puppetserver
    parser = current
    rundir = /var/run/puppetserver
    ssldir = /etc/puppet/ssl
    strict_variables = false
    vardir = /opt/puppet/server/data/puppetserver
    external_nodes = /etc/puppet/node.rb
    node_terminus = exec
EOF

chown puppet:foreman /var/run/puppetserver/restartcounter

systemctl enable --now puppet
systemctl enable --now puppetserver

echo -e "\nDownload archives"
echo -e "   download and unpack: '${store}/ruby_portable-2.5.9-3.tar.gz'"
wget -qO- "${store}/ruby_portable-2.5.9-3.tar.gz" | tar xz -C /opt
[[ "$?" -ne 0 ]] && ( echo "error download ${store}/ruby_portable-2.5.9-3.tar.gz"; exit 1 )

echo -e "   download: '${store}/node.rb'"
wget -qO- "${store}/node.rb" > /etc/puppet/node.rb
[[ "$?" -ne 0 ]] && ( echo "error download ${store}/node.rb"; exit 1 )

chmod +x /etc/puppet/node.rb

echo -e "   download ${store}/${store}/puppet-modules.tar.gz"
wget -qO- "${store}/puppet-modules.tar.gz" | tar xz -C /usr/lib

cat << EOF > /etc/puppet/foreman.yaml
---
# Update for your Foreman and Puppet master hostname(s)
:url: "http://$(hostname -f):2345"
:ssl_ca: "/etc/puppet/ssl/certs/ca.pem"
:ssl_cert: "/etc/puppet/ssl/certs/$(hostname -f).pem"
:ssl_key: "/etc/puppet/ssl/private_keys$(hostname -f).pem"

# Advanced settings
:puppetdir: "/var/lib/puppetserver"
:puppetuser: "puppet"
:facts: true
:timeout: 40
:threads: null

EOF

echo -e "\nSetup enviroments"
export PATH="/opt/ruby/bin:$PATH"
export LD_LIBRARY_PATH=/opt/ruby/lib64/:$LD_LIBRARY_PATH
export GEM_HOME="/opt/ruby/lib/ruby/gems/2.5.0"
export GEM_PATH="$GEM_HOME"

export RUBYOPT=-W0
export RAILS_ENV=production

# ----------------------- smart-proxy -----------------------------
mkdir -p /etc/smart-proxy/config/settings.d
mkdir -p /var/lib/smart-proxy
mkdir -p /var/log/smart-proxy
mkdir -p /run/smart-proxy

cat << EOF > /etc/smart-proxy/config/settings.d/puppet.yml
---
# Can be true, false, or http/https to enable just one of the protocols
:enabled: http
# valid providers:
#   puppet_proxy_mcollective (uses mco puppet)
#   puppet_proxy_ssh         (run puppet over ssh)
#   puppet_proxy_salt        (uses salt puppet.run)
#   puppet_proxy_customrun   (calls a custom command with args)
#:use_provider: puppet_proxy_customrun
:puppet_version: $(rpm -q puppetserver | cut -d "-" -f 2)
EOF

cat << EOF > /etc/smart-proxy/config/settings.d/facts.yml
---
:enabled: true
EOF

cat << EOF > /etc/smart-proxy/config/settings.d/puppetca_http_api.yml
---
:puppet_url: https://$(hostname -f):8140
:puppet_ssl_ca: /etc/puppet/ssl/certs/ca.pem
:puppet_ssl_cert: /etc/puppet/ssl/certs/$(hostname -f).pem
:puppet_ssl_key: /etc/puppet/ssl/private_keys/$(hostname -f).pem

EOF

cat << EOF > /etc/smart-proxy/config/settings.d/puppet_proxy_puppet_api.yml
---
:puppet_url: https://$(hostname -f):8140
:puppet_ssl_ca: /etc/puppet/ssl/certs/ca.pem
:puppet_ssl_cert: /etc/puppet/ssl/certs/$(hostname -f).pem
:puppet_ssl_key: /etc/puppet/ssl/private_keys/$(hostname -f).pem

EOF

cat << EOF > /etc/smart-proxy/config/settings.d/puppetca_hostname_whitelisting.yml
---
:autosignfile: /etc/puppet/autosign.conf

EOF

cat << EOF > /etc/smart-proxy/config/settings.d/puppetca.yml
---
:enabled: http
:use_provider: puppetca_hostname_whitelisting
:puppet_version: 6.19.0

EOF

cat << EOF > /etc/smart-proxy/config/settings.d/logs.yml
---
:enabled: http

EOF

cat << EOF > /etc/smart-proxy/config/settings.yml
---
:foreman_url: http://127.0.0.1:2345
:daemon: true
:daemon_pid: /run/smart-proxy/smart-proxy.pid
:bind_host: ['*']
:http_port: 8000
:log_file: /var/log/smart-proxy/proxy.log
:log_level: ERROR
:file_rolling_size: 1024
:file_rolling_age: weekly
:file_rolling_keep: 6
:file_logging_pattern: '%d %.8X{request} [%.1l] %m'
:system_logging_pattern: '%m'
:log_buffer: 2000
:log_buffer_errors: 1000
:dns_resolv_timeouts: [5, 8, 13]

EOF

cat << EOF > /lib/systemd/system/smart-proxy.service
[Unit]
Description=Foreman Smart Proxy
Documentation=https://projects.theforeman.org/projects/smart-proxy/wiki
After=network.target remote-fs.target nss-lookup.target puppet.service puppetserver.service
Wants=puppet.service puppetserver.service

[Service]
Type=forking
User=smartforeman
NotifyAccess=all
PIDFile=/run/smart-proxy/smart-proxy.pid
WorkingDirectory=/var/lib/smart-proxy
ExecStart=/bin/bash -lc 'exec /opt/ruby/bin/smart-proxy'
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
LimitCORE=infinity
Restart=on-failure
StandardInput=null
SyslogIdentifier=%n

[Install]
WantedBy=multi-user.target

EOF

cat << EOF > /opt/ruby/bin/smart-proxy
#!/usr/bin/env ruby

\$LOAD_PATH.unshift(*Dir[File.expand_path("../../lib", __FILE__), File.expand_path("../../modules", __FILE__)])

require 'smart_proxy_main'
Proxy::Launcher.new.launch

EOF

cat << EOF > /var/lib/smart-proxy/.bash_profile
# ~/.bash_profile

# Source global definitions.
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

# Read /etc/inputrc if the variable is not defined.
[ -n "\$INPUTRC" ] || export INPUTRC=/etc/inputrc

export USERNAME=smartforeman

export RUBYOPT=-W0
export RAILS_ENV=production

export PATH="/opt/ruby/bin:\$PATH"
export LD_LIBRARY_PATH=/opt/ruby/lib64/:\$LD_LIBRARY_PATH
export GEM_HOME="/opt/ruby/lib/ruby/gems/2.5.0"
export GEM_PATH="\$GEM_HOME"

EOF

cat << EOF > /var/lib/smart-proxy/Gemfile

source 'https://rubygems.org'

gem 'smart_proxy'

if RUBY_VERSION < '2.2'
  gem 'sinatra', '< 2'
  gem 'rack', '>= 1.3', '< 2.0.0'
end
gem 'concurrent-ruby', '~> 1.0', require: 'concurrent'

Dir["#{File.dirname(__FILE__)}/bundler.d/*.rb"].each do |bundle|
  self.instance_eval(Bundler.read_file(bundle))
end

gem 'smart_proxy_dynflow', '~> 0.2.4'
gem 'smart_proxy_remote_execution_ssh', '~> 0.2.1'
#gem 'smart_proxy_ansible', '~> 3.0.1'
#gem 'smart_proxy_discovery', '~> 1.0.5'
#gem 'smart_proxy_pulp', '~> 2.1.0'
#gem 'smart_proxy_chef', '~> 0.2.0'

EOF

echo -e "\nCreate user smartforeman"
getent group smartforeman >/dev/null || groupadd -r smartforeman
useradd -r -g smartforeman -G foreman,puppet -d /var/lib/smart-proxy -s /bin/bash smartforeman

chown -R smartforeman:smartforeman /var/lib/smart-proxy
chown -R smartforeman:smartforeman /var/log/smart-proxy

chown -R smartforeman:foreman /run/smart-proxy
chmod 751 /run/smart-proxy

chmod +x /opt/ruby/bin/smart-proxy

echo -e "\nStart smart-proxy"
systemctl daemon-reload
systemctl enable --now smart-proxy

sleep 5


# ---------------- smart_proxy_dynflow_core -------------
mkdir -p /etc/smart_proxy_dynflow_core/

cat << EOF > /etc/smart_proxy_dynflow_core/settings.yml
---
# Path to dynflow database, leave blank for in-memory non-persistent database
:database:

# URL of the foreman, used for reporting back
:foreman_url: 'http://$(hostname):2345'

# SSL settings for client authentication against Foreman
:foreman_ssl_ca: /etc/puppet/ssl/certs/ca.pem
:foreman_ssl_cert: /etc/puppet/ssl/certs/$(hostname).pem
:foreman_ssl_key: /etc/puppet/ssl/private_keys/$(hostname).pem

:console_auth: false

# Set to true to make the core fork to background after start
# :daemonize: false
# :pid_file: /var/run/foreman-proxy/smart_proxy_dynflow_core.pid

# Listen on address
:listen: 127.0.0.1

# Listen on port
:port: 8008

# SSL settings for running core as https service
# :use_https: false
# :ssl_ca_file: /etc/puppet/ssl/certs/ca.pem
# :ssl_certificate: /etc/puppet/ssl/certs/$(hostname).pem
# :ssl_private_key: /etc/puppet/ssl/private_keys/$(hostname).pem

# Use this option only if you need to disable certain cipher suites.
# Note: we use the OpenSSL suite name, take a look at:
# https://www.openssl.org/docs/manmaster/apps/ciphers.html#CIPHER-SUITE-NAMES
# for more information.
#:ssl_disabled_ciphers: [CIPHER-SUITE-1, CIPHER-SUITE-2]

# Use this option only if you need to strictly specify TLS versions to be
# disabled. SSLv3 and TLS v1.0 are always disabled and cannot be configured.
# Specify versions like: '1.1', or '1.2'
#:tls_disabled_versions: []

# File to log to, leave empty for logging to STDOUT
:log_file: /var/log/smart-proxy/smart_proxy_dynflow_core.log

# Log level, one of UNKNOWN, FATAL, ERROR, WARN, INFO, DEBUG
# :log_level: ERROR

# Maximum age of execution plans to keep before having them cleaned
# by the execution plan cleaner (in seconds), defaults to 24 hours
# :execution_plan_cleaner_age: 86400

EOF

mkdir -p /var/lib/smart-proxy-dynflow-core
mkdir -p /run/smart-proxy-dynflow-core


cat << EOF > /lib/systemd/system/smart-proxy-dynflow-core.service
[Unit]
Description=Foreman smart proxy dynflow core service
Documentation=https://github.com/theforeman/smart_proxy_dynflow
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=notify
User=smartforeman
WorkingDirectory=/var/lib/smart-proxy-dynflow-core
PIDFile=/run/smart-proxy-dynflow-core/smart-proxy-dynflow-core.pid
ExecStart=/bin/bash -lc 'bundle exec /opt/ruby/bin/smart_proxy_dynflow_core --no-daemonize -p /run/smart-proxy-dynflow-core/smart-proxy-dynflow-core.pid'
EnvironmentFile=-/etc/sysconfig/smart-proxy-dynflow-core

[Install]
WantedBy=multi-user.target

EOF

cat << EOF > /var/lib/smart-proxy-dynflow-core/Gemfile
gem 'smart_proxy_dynflow_core'
gem 'foreman_remote_execution_core', '~> 1.4.0'
gem 'ed25519'
gem 'bcrypt_pbkdf'

EOF

chown -R smartforeman:smartforeman /var/lib/smart-proxy-dynflow-core
chown -R smartforeman:smartforeman /run/smart-proxy-dynflow-core

systemctl daemon-reload
systemctl enable --now smart-proxy-dynflow-core


cat << EOF > /etc/tmpfiles.d/tmpfiles-foreman-smart-proxy.conf
#
d /var/log/smart-proxy/ 0775 smartforeman smartforeman -
d /run/smart-proxy/ 0751 smartforeman foreman -
d /run/smart-proxy-dynflow-core/ 0755 smartforeman smartforeman -

EOF
