#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# Author:: Adam Jacob (<adam@opscode.com>)
#

require 'uuidtools'
require 'openssl'

# Because these symlinks get removed during the postrm
# of the chef-server and private-chef packages, we should
# ensure that they're always here.
%w{private-chef-ctl chef-server-ctl}.each do |bin|
  link "/usr/bin/#{bin}" do
    to "/opt/opscode/bin/#{bin}"
  end
end

# Ensure that all our Omnibus-ed binaries are the ones that get used;
# much better than having to specify this on each resource!
ENV['PATH'] = "/opt/opscode/bin:/opt/opscode/embedded/bin:#{ENV['PATH']}"

directory "/etc/opscode" do
  owner "root"
  group "root"
  mode "0755"
  action :nothing
end.run_action(:create)

directory "/etc/opscode/logrotate.d" do
  owner "root"
  group "root"
  mode "0755"
  action :nothing
end.run_action(:create)

include_recipe "private-chef::plugin_discovery"
include_recipe "private-chef::plugin_config_extensions"
include_recipe "private-chef::config"

# Warn about deprecated opscode_webui settings
opscode_webui_deprecation_notice = OpscodeWebuiDeprecationNotice.new(
  PrivateChef['opscode_webui']
)
log 'opscode_webui deprecation notice' do
  message opscode_webui_deprecation_notice.message
  level :warn
  only_if { opscode_webui_deprecation_notice.applicable? }
end

# @todo: This seems like it might belong in the PrivateChef helper;
#   many other attributes like are set automatically there as well.
if OmnibusHelper.has_been_bootstrapped?
  node.set['private_chef']['bootstrap']['enable'] = false
end

# Create the Chef User
include_recipe "private-chef::users"

# merge xdarklaunch values into the disk-based darklaunch
# so that we have a single source of truth for xdl-related
# values
darklaunch_values = node['private_chef']['dark_launch']
  .merge(node['private_chef']['lb']['xdl_defaults'])
  .to_hash

file "/etc/opscode/dark_launch_features.json" do
  owner OmnibusHelper.new(node).ownership['owner']
  group "root"
  mode "0644"
  content Chef::JSONCompat.to_json_pretty(darklaunch_values)
end

webui_key = OpenSSL::PKey::RSA.generate(2048) unless File.exists?('/etc/opscode/webui_pub.pem')

file "/etc/opscode/webui_pub.pem" do
  owner "root"
  group "root"
  mode "0644"
  content webui_key.public_key.to_s unless File.exists?('/etc/opscode/webui_pub.pem')
end

file "/etc/opscode/webui_priv.pem" do
  owner OmnibusHelper.new(node).ownership['owner']
  group "root"
  mode "0600"
  content webui_key.to_pem.to_s unless File.exists?('/etc/opscode/webui_pub.pem')
end

worker_key = OpenSSL::PKey::RSA.generate(2048) unless File.exists?('/etc/opscode/worker-public.pem')

file "/etc/opscode/worker-public.pem" do
  owner "root"
  group "root"
  mode "0644"
  content worker_key.public_key.to_s unless File.exists?('/etc/opscode/worker-public.pem')
end

file "/etc/opscode/worker-private.pem" do
  owner OmnibusHelper.new(node).ownership['owner']
  group "root"
  mode "0600"
  content worker_key.to_pem.to_s unless File.exists?('/etc/opscode/worker-public.pem')
end

# If we are doing initial key generation,
# generate a new key.
unless File.exists?('/etc/opscode/pivotal.pem')
  pivotal_key = OpenSSL::PKey::RSA.generate(2048)
end

# This will be cleaned up during bootstrap.
# Only generate if pivotal.pem doesn't exist,
# because that means we are doing initial key generation
# per the step directly above.
unless File.exists?('/etc/opscode/pivotal.pem')
  file "/etc/opscode/pivotal.pub" do
    owner OmnibusHelper.new(node).ownership['owner']
    group "root"
    mode "0644"
    content pivotal_key.public_key.to_s
  end
end

# If we are doing initial key generation (aka pivotal.pem hasn't yet
# been created), create pivotal.pem.
file "/etc/opscode/pivotal.pem" do
  owner OmnibusHelper.new(node).ownership['owner']
  group "root"
  mode "0600"
  content pivotal_key.to_pem.to_s unless File.exists?('/etc/opscode/pivotal.pem')
end

directory "/etc/chef" do
  owner "root"
  group OmnibusHelper.new(node).ownership['group']
  mode "0775"
  action :create
end

directory "/var/opt/opscode" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

directory "/var/log/opscode" do
  owner OmnibusHelper.new(node).ownership['owner']
  group OmnibusHelper.new(node).ownership['group']
  mode "0755"
  action :create
end

# Put keepalived into a safe state before proceeding with
# the opscode-runsvdir -> opscode-private-chef transition
private_chef_keepalived_safemode 'warmfuzzy' do
  only_if { ha? }
  only_if { is_data_master? }
  only_if 'initctl status opscode-runsvdir | grep start'
end

include_recipe "enterprise::runit"
include_recipe "private-chef::sysctl-updates"
# Run plugins first, mostly for ha
include_recipe "private-chef::plugin_chef_run"

# If the add-on repository exists, include the recipe
# to ensure that it's disabled.  Since chef-server-core
# lives in the same repository as the add-ons, this
# avoids unplanned upgrades to chef-server-core
if OmnibusHelper.new(node).repository_configured? "chef-stable"
  include_recipe "private-chef::add_ons_repository"
end

# Configure Services
[
  "rabbitmq",
  "postgresql",
  "sqeache",
  "oc_bifrost",
  "oc_id",
  "opscode-solr4",
  "opscode-expander",
  "bookshelf",
  "opscode-erchef",
  "bootstrap",
  "opscode-chef-mover",
  "redis_lb",
  "nginx",
  "keepalived"
].each do |service|
  if node["private_chef"][service]["external"]
    begin
      # Perform any necessary configuration of the external service:
      include_recipe "private-chef::#{service}-external"
    rescue Chef::Exceptions::RecipeNotFound
      raise "#{service} has the 'external' attribute set true, but does not currently support being run externally."
    end
    # Disable the actual local service since what is enabled
    # is an externally managed version. Given that bootstrap and
    # opscode-expander are not externalizable, don't need special
    # handling for them as we do in the normal disable case below.
    runit_service service do
      action :disable
    end
  else
    if node["private_chef"][service]["enable"]
      include_recipe "private-chef::#{service}"
    else
      # bootstrap isn't a service, nothing to disable.
      next if service == 'bootstrap'
      # All non-enabled services get disabled;
      runit_service service do
        action :disable
      end
      # opscode-expander is paired with expander-reindexer,
      # so disable that too.
      if service == 'opscode-expander'
        runit_service 'opscode-expander-reindexer' do
          action :disable
        end
      end
    end
  end
end

include_recipe "private-chef::actions" if darklaunch_values["actions"]

include_recipe "private-chef::private-chef-sh"
include_recipe "private-chef::oc-chef-pedant"
include_recipe "private-chef::log_cleanup"
include_recipe "private-chef::partybus"
include_recipe "private-chef::ctl_config"
include_recipe "private-chef::disable_chef_server_11"

file "/etc/opscode/chef-server-running.json" do
  owner OmnibusHelper.new(node).ownership['owner']
  group "root"
  mode "0600"

  file_content = {
    "private_chef" => node['private_chef'].to_hash,
    "run_list" => node.run_list,
    "runit" => node['runit'].to_hash
  }
  # back-compat fixes for opscode-reporting
  # reporting uses the opscode-solr key for determining the location of the solr host,
  # so we'll copy the contents over from opscode-solr4
  file_content['private_chef']['opscode-solr'] ||= {}
  %w{vip port}.each do |key|
    file_content['private_chef']['opscode-solr'][key] = file_content['private_chef']['opscode-solr4'][key]
  end

  content Chef::JSONCompat.to_json_pretty(file_content)
end
