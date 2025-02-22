#!/usr/bin/env bash

store="https://github.com/voldmir/install_foreman/releases/download/v1.0.3"

apt-get update

apt-get install java-21-openjdk -y
apt-get install puppetserver puppet -y
apt-get install node-sass node -y
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

apt-get install postgresql16-server postgresql16 -y

/etc/init.d/postgresql initdb

echo -e "\nlisten_addresses = 'localhost'" >> /var/lib/pgsql/data/postgresql.conf

systemctl enable postgresql --now

createuser -U postgres --createdb --no-createrole foreman

echo -e "\nDownload archives"

echo -e "   download and unpack: '${store}/ruby_portable-2.5.9-3.tar.gz'"
wget -qO- "${store}/ruby_portable-2.5.9-3.tar.gz" | tar xz -C /opt
[[ "$?" -ne 0 ]] && ( echo "error download ${store}/ruby_portable-2.5.9-3.tar.gz"; exit 1 )

echo -e "   download and unpack: '${store}/foreman_portable-1.23.4-3.tar.gz'"
wget -qO- "${store}/foreman_portable-1.23.4-3.tar.gz" | tar xz -C /opt
[[ "$?" -ne 0 ]] && ( echo "error download ${store}/foreman_portable-1.23.4-3.tar.gz"; exit 1 )

echo -e "   download: '${store}/node.rb'"
wget -qO- "${store}/node.rb" > /etc/puppet/node.rb
[[ "$?" -ne 0 ]] && ( echo "error download ${store}/node.rb"; exit 1 )

chmod +x /etc/puppet/node.rb

echo -e "   download ${store}/${store}/puppet-modules.tar.gz"
wget -qO- "${store}/puppet-modules.tar.gz" | tar xz -C /usr/lib

echo -e "\nCreate user foreman"
getent group foreman >/dev/null || groupadd -r foreman
useradd -r -g foreman -d /var/lib/foreman -s /bin/bash foreman

echo #Create directories"
mkdir -p /etc/cron.d
mkdir -p /var/lib/foreman
mkdir -p /var/log/foreman
mkdir -p /etc/foreman/plugins
mkdir -p /var/cache/foreman/{_,openid-store}
mkdir -p /var/spool/foreman/tmp
mkdir -p /var/www/foreman
mkdir -p /var/run/foreman

ln -s /var/log/foreman /opt/foreman/log

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

echo -e "\nCreate files"
cat << EOF > /etc/foreman/settings.yml
---
:unattended: false
#:require_ssl: true

# The following values are used for providing default settings during db migrate
:oauth_active: true
:oauth_map_users: false
:oauth_consumer_key: DuUFfg3JkQrpgdHCyFFemBbRLQFmYfCQ
:oauth_consumer_secret: FAWoGgBVk736RjRvGmR69hEQmgX3oVi3

# Websockets
:websockets_encrypt: true
:websockets_ssl_key: /etc/puppet/ssl/private_keys/$(hostname -f).pem
:websockets_ssl_cert: /etc/puppet/ssl/certs/$(hostname -f).pem

# SSL-settings
:ssl_certificate: /etc/puppet/ssl/certs/$(hostname -f).pem
:ssl_ca_file: /etc/puppet/ssl/certs/ca.pem
:ssl_priv_key: /etc/puppet/ssl/private_keys/$(hostname -f).pem

# HSTS setting
:hsts_enabled: true

:logging:
  :level: debug
  :production:
    :type: file
    :layout: pattern

:loggers:

:telemetry:
  :prefix: 'fm_rails'
  :prometheus:
    :enabled: false
  :statsd:
    :enabled: false
    :host: '127.0.0.1:8125'
    :protocol: 'statsd'
  :logger:
    :enabled: false
    :level: 'DEBUG'

:dynflow:
  :pool_size: 5

EOF

cat << EOF > /etc/foreman/local_secret_token.rb
# Be sure to restart your server when you modify this file.

# Your secret key for verifying the integrity of signed cookies.
# If you change this key, all old signed cookies will become invalid!
# Make sure the secret is at least 30 characters and all random,
# no regular words or you'll be exposed to dictionary attacks.

# You can use \`rake security:generate_token\` to regenerate this file.

Foreman::Application.config.secret_token = ''

EOF

cat << EOF > /etc/foreman/encryption_key.rb
# Be sure to restart your server when you modify this file.

# Your encryption key for encrypting and decrypting database fields.
# If you change this key, all encrypted data will NOT be able to be decrypted by Foreman!
# Make sure the key is at least 32 bytes such as SecureRandom.hex(20)

# You can use \`rake security:generate_encryption_key\` to regenerate this file.

module EncryptionKey
  ENCRYPTION_KEY = ''
end

EOF

cat << EOF > /etc/foreman/foreman-debug.conf
# Configuration file for foreman-debug utility

# Directory to place the tarball in (string)
#DIR=

# Skip generic info (0 or 1)
#NOGENERIC=0

# Do not create tarballs (0 or 1)
#NOTAR=0

# Maximum size for output files in bytes (integer)
#MAXSIZE=10485760   # 10 MB

# Compress program to pipe the tarball through (string)
#COMPRESS=

# Print passwords which are filtered out on stdout (0 or 1)
#PRINTPASS=0

# Quiet mode (0 or 1)
#QUIET=0

# Verbose mode (0 or 1)
#VERBOSE=1

# Debug mode (0 or 1)
#DEBUG=1

# Upload tarball after each run (0 or 1)
#UPLOAD=0

# Permanently disable upload feature (0 or 1)
#UPLOAD_DISABLED=0

# URL of the upload location (string)
#UPLOAD_URL='rsync://theforeman.org/debug-incoming'

# The full upload command in strict quotes (string)
#UPLOAD_CMD='rsync "\${TARBALL}" "\${UPLOAD_URL}"'

# Additional help message for when uploads are not disabled (UPLOAD_DISABLED=0) (multi line string)
#UPLOAD_USAGE_MSG="\
#Add your custom message here."

# Message displayed at the end if neither UPLOAD nor UPLOAD_DISABLED is set (multi line string)
#UPLOAD_UNSET_MSG="\
#Add your custom message here."

# Message when an upload was successfull (multi line string)
# note: will be appended with "\$(basename \${TARBALL})\n"
#UPLOAD_SUCCESS_MSG="\
#Add your custom message here."

# Message when an upload was not successfull (multi line string)
#UPLOAD_FAIL_MSG="\
#Add your custom message here."

# Tokens that are fileted out (shell array)
#FILTER_WORDS=(pass password token key)

EOF

cat << EOF > /etc/foreman/database.yml
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 30 } %>
  database: <%= ENV.fetch("DATABASE_NAME") { "foreman_production" } %>
  username: <%= ENV.fetch("DATABASE_USERNAME") { "foreman" } %>
  password: <%= ENV.fetch("DATABASE_PASSWORD") { "" } %>

EOF

cat << EOF > /var/lib/foreman/.bash_profile
# ~/.bash_profile

# Source global definitions.
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

export USERNAME=foreman

export RUBYOPT=-W0
export RAILS_ENV=production

export PATH="/opt/ruby/bin:\$PATH"
export LD_LIBRARY_PATH=/opt/ruby/lib64/:\$LD_LIBRARY_PATH
export GEM_HOME="/opt/ruby/lib/ruby/gems/2.5.0"
export GEM_PATH="\$GEM_HOME"

EOF

cat << EOF >  /lib/systemd/system/foreman.service
[Unit]
Description=Foreman
Documentation=https://theforeman.org
After=network.target remote-fs.target nss-lookup.target
Requires=postgresql.service

[Service]
Type=simple
User=foreman
WorkingDirectory=/opt/foreman
Environment=PORT=%i
Environment="RAILS_MAX_THREADS=20"
Environment="MAX_THREADS=20"
Environment="CACHE=true"
Environment="RAILS_ENV=production"
ExecStart=/bin/bash -lc 'exec /opt/ruby/bin/railsctl run foreman /opt/ruby/bin/rails s -p \${PORT:-2345} -e \$RAILS_ENV'
Restart=always
StandardInput=null
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=%n
KillMode=mixed
TimeoutStopSec=300
TimeoutSec=300

[Install]
WantedBy=multi-user.target

EOF

cat << EOF >  /lib/systemd/system/foreman-jobs.service
[Unit]
Description=Foreman jobs service
Documentation=https://theforeman.org
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
User=root
TimeoutSec=90
WorkingDirectory=/var/lib/foreman
EnvironmentFile=-/etc/sysconfig/foreman-jobs

ExecStart=/opt/ruby/bin/bundle exec /opt/ruby/bin/dynflow start
ExecReload=/opt/ruby/bin/bundle exec /opt/ruby/bin/dynflow restart
ExecStop=/opt/ruby/bin/bundle exec /opt/ruby/bin/dynflow stop

[Install]
WantedBy=multi-user.target

EOF


cat << EOF > /etc/cron.d/foreman
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/opt/foreman/script:/usr/bin

RAILS_ENV=production
FOREMAN_HOME=/opt/foreman

1 */2 * * * root  /bin/chown -R foreman:root /var/cache/foreman

# Clean up the session entries in the database
15 23 * * *     root    /opt/foreman/script/foreman-rake db:sessions:clear >>/var/log/foreman/cron.log 2>&1

# Send out recurring notifications
0 7 * * *       root    /opt/foreman/script/foreman-rake reports:daily >>/var/log/foreman/cron.log 2>&1
0 5 * * 0       root    /opt/foreman/script/foreman-rake reports:weekly >>/var/log/foreman/cron.log 2>&1
0 3 1 * *       root    /opt/foreman/script/foreman-rake reports:monthly >>/var/log/foreman/cron.log 2>&1

# Expire old reports
30 7 * * *      root    /opt/foreman/script/foreman-rake reports:expire >>/var/log/foreman/cron.log 2>&1

# Collects trends data
*/30 * * * *    root    /opt/foreman/script/foreman-rake trends:counter >>/var/log/foreman/cron.log 2>&1

# Refreshes ldap usergroups. Can be disabled if you're not using LDAP authentication.
#*/30 * * * *    root    /opt/foreman/script/foreman-rake ldap:refresh_usergroups >>/var/log/foreman/cron.log 2>&1

# Clean expired notifications
0 6 * * 0       root    /opt/foreman/script/foreman-rake notifications:clean >>/var/log/foreman/cron.log 2>&1

# Only use the following cronjob if you're not using the ENC or ActiveRecord-based storeconfigs
# Get the node.rb / ENC script and store at /etc/puppet/node.rb:
#   https://github.com/theforeman/puppet-foreman/blob/master/templates/external_node.rb.erb
# Send facts to Foreman, using the ENC script in a fact pushing only mode
#*/2 * * * *     root    /usr/bin/tfm-ruby /etc/puppet/node.rb --push-facts >>/var/log/foreman/cron.log 2>&1

# Warning: ActiveRecord-based storeconfigs is deprecated from Foreman 1.1 and Puppet 3.0
#   see http://projects.theforeman.org/wiki/foreman/ReleaseNotes#11-stable
# Only use the following cronjob if you're using ActiveRecord storeconfigs!
#*/30 * * * *    root    /opt/foreman/script/foreman-rake puppet:migrate:populate_hosts >>/var/log/foreman/cron.log 2>&1

EOF

cat << EOF > /etc/logrotate.d/foreman
# Foreman logs:
/var/log/foreman/*.log {
  daily
  missingok
  rotate 14
  compress
  delaycompress
  notifempty
  copytruncate
}

EOF

cat << EOF > /etc/sysconfig/foreman
# the location where foreman is installed
#FOREMAN_HOME=/opt/foreman

# the port which foreman web server is running at
# note that if the foreman user is not root, it has to be a > 1024
#FOREMAN_PORT=2345

# the user which runs the web interface
#FOREMAN_USER=foreman

# the rails environment in which foreman runs
#FOREMAN_ENV=production

# if we're using passenger or not
# if set to 1, init script will do a railsrestart on 'restart' and will refuse
# 'start' and 'stop' completely and remind the operator that passenger is in
# use.
#FOREMAN_USE_PASSENGER=0

EOF

cat << EOF > /etc/sysconfig/foreman-jobs
### Mandatory variables
EXECUTOR_USER=foreman
EXECUTOR_PID_DIR=/var/run/foreman
EXECUTOR_LOG_DIR=/var/log/foreman
EXECUTOR_ROOT=/opt/foreman
RAILS_ENV=production
BUNDLE_GEMFILE=/var/lib/foreman/Gemfile

RUBY_GC_MALLOC_LIMIT=4000100
RUBY_GC_MALLOC_LIMIT_MAX=16000100
RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR=1.1
RUBY_GC_OLDMALLOC_LIMIT=16000100
RUBY_GC_OLDMALLOC_LIMIT_MAX=16000100

### Optional variables
# Set the number of executors you want to run
# EXECUTORS_COUNT=1

# Set memory limit for executor process, before it's restarted automatically
# EXECUTOR_MEMORY_LIMIT=2gb

# Set delay before first memory polling to let executor initialize (in sec)
# EXECUTOR_MEMORY_MONITOR_DELAY=7200 #default: 2 hours

# Set memory polling interval, process memory will be checked every N seconds.
# EXECUTOR_MEMORY_MONITOR_INTERVAL=60

# Custom ruby
PATH="/opt/ruby/bin:/var/lib/foreman/bin:/bin:/usr/bin:/usr/local/bin:/usr/games:/var/cache/ruby/gemie/bin:/usr/lib/ruby/bin"
LD_LIBRARY_PATH=/opt/ruby/lib64/
GEM_HOME="/opt/ruby/lib/ruby/gems/2.5.0"
GEM_PATH="/opt/ruby/lib/ruby/gems/2.5.0"

EOF

echo -e "\nCreate symlinks"
ln -s /etc/foreman/plugins /opt/foreman/config/settings.plugins.d
ln -s /etc/foreman/settings.yml /opt/foreman/config/settings.yml
ln -s /etc/foreman/foreman-debug.conf /opt/foreman/config/foreman-debug.yml
ln -s /etc/foreman/database.yml /opt/foreman/config/database.yml
ln -s /var/cache/foreman/_ /var/spool/foreman/tmp/cache

echo -e "\nSetup permissions"
chown -R foreman:foreman /etc/foreman
chown -R foreman:foreman /var/lib/foreman
chown -R foreman:foreman /var/log/foreman
chown -R foreman:foreman /var/cache/foreman
chown -R foreman:foreman /var/spool/foreman
chown -R foreman:foreman /var/www/foreman
chown -R foreman:foreman /var/run/foreman

echo -e "\nSetup enviroments"
export PATH="/opt/ruby/bin:$PATH"
export LD_LIBRARY_PATH=/opt/ruby/lib64/:$LD_LIBRARY_PATH
export GEM_HOME="/opt/ruby/lib/ruby/gems/2.5.0"
export GEM_PATH="$GEM_HOME"

export RUBYOPT=-W0
export RAILS_ENV=production

echo -e "\nStart setup foreman"
/opt/ruby/bin/railsctl setup foreman

sed -i 's/RAKE_CMD=\/usr\/bin\/rake/RAKE_CMD=\/opt\/ruby\/bin\/rake/g' /opt/foreman/script/foreman-rake

systemctl daemon-reload
systemctl enable --now foreman

systemctl enable --now foreman-jobs

echo -e "Open site:\n    http://$(hostname -f):2345"

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
# -----------------------------

creds=$(grep "Login credentials" /var/log/foreman/ -r | sed "s,.*:Log,Log," | tail -1 | cut -d ":" -f 2 | awk -F/ 'gsub(/ */,"",$0){print $1":"$2}')

if [[ -n $creds ]] ; then
    
    if /sbin/systemctl is-active "foreman.service" &>/dev/null ; then
        
        echo -e "\nRegestration smart-proxy"
        
        count=0
        while [ $count -lt 300 ] ; do
            (( count++ ))
            nc -vz $(hostname -f) 2345 &>/dev/null
            [ "$?" -eq 0 ] && count=301
            echo -n "."
            sleep 1
        done
        
        echo ""
        curl --silent --request POST \
        --header "Accept:application/json" \
        --header "Content-Type:application/json" \
        --user "$creds" \
        --data "{\"smart_proxy\":{\"name\":\"$(hostname -f)\",\"url\":\"http://$(hostname -f):8000\"}}" \
        http://$(hostname -f):2345/api/smart_proxies &>/dev/null
        
        [ "$?" -eq 0 ] && echo "Smart-proxy registration success" || echo "Error registration smart-proxy"
        
        curl --silent --request POST \
        --header "Accept:application/json" \
        --header "Content-Type:application/json" \
        --user "$creds" \
        --data "{\"environment\": {\"name\": \"production\"}}" \
        http://$(hostname -f):2345/api/environments &>/dev/null


        curl --silent --request PUT \
        --header "Accept:application/json" \
        --header "Content-Type:application/json" \
        --user "$creds" \
        --data "{\"setting\":{\"value\":\"[$(hostname -f),$(hostname -s),$(hostname -i)]\"}}" \
        http://$(hostname -f):2345/api/settings/trusted_hosts

        systemctl restart foreman

    fi
    echo
    su -l -s "/bin/bash" postgres -c "psql -d foreman_production -c 'CREATE INDEX dynflow_actions_execution_plan_uuid_id_index ON public.dynflow_actions USING btree (execution_plan_uuid, id);'"
    echo
    su -l -s "/bin/bash" postgres -c "psql -d foreman_production -c 'CREATE UNIQUE INDEX dynflow_execution_plans_uuid_index ON public.dynflow_execution_plans USING btree (uuid);'"
    echo
    su -l -s "/bin/bash" postgres -c "psql -d foreman_production -c 'CREATE INDEX dynflow_steps_execution_plan_uuid_id_index ON public.dynflow_steps USING btree (execution_plan_uuid, id);'"
    echo
fi


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
d /var/log/foreman/ 0755 foreman foreman -
d /run/foreman/ 0755 foreman foreman -
d /run/smart-proxy/ 0751 smartforeman foreman -
d /run/smart-proxy-dynflow-core/ 0755 smartforeman smartforeman -

EOF
