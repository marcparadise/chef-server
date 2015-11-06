# Authorx: Marc Paradise <marc@chef.io>
# Copyright: Copyright (c) 2015 Chef Software, Inc
#            Copying, using, or modifying this file constitutes
#            acceptance of all terms specified under the
#            Apache Software License v2

sqeache_dir = node['private_chef']['sqeache']['dir']
sqeache_etc_dir = File.join(sqeache_dir, "etc")
sqeache_log_dir = node['private_chef']['sqeache']['log_directory']
sqeache_sasl_log_dir = File.join(sqeache_log_dir, "sasl")
[
  sqeache_dir,
  sqeache_etc_dir,
  sqeache_log_dir,
  sqeache_sasl_log_dir
].each do |dir_name|
  directory dir_name do
    owner OmnibusHelper.new(node).ownership['owner']
    group OmnibusHelper.new(node).ownership['group']
    mode node['private_chef']['service_dir_perms']
    recursive true
  end
end

link "/opt/opscode/embedded/service/sqeache/log" do
  to sqeache_log_dir
end


sqeache_config = File.join(sqeache_dir, "sys.config")

template sqeache_config do
  source "sqeache.config.erb"
  owner OmnibusHelper.new(node).ownership['owner']
  group OmnibusHelper.new(node).ownership['group']
  mode "644"
  variables(
            pg_vip: node['private_chef']['postgresql']['vip'],
            pg_port: node['private_chef']['postgresql']['port'],
            sql_user: node['private_chef']['opscode-erchef']['sql_user'],
            sql_password: node['private_chef']['opscode-erchef']['sql_password'],
            sqeache: node['private_chef']['sqeache'],
            pools: node['private_chef']['sqeache']['pools'],
            postgresql: node['private_chef']['postgresql'])
  notifies :run, 'execute[remove_sqeache_siz_files]', :immediately
  # NOte - we'll want to keep both nodes active for sqeache...
  notifies :restart, 'runit_service[sqeache]' unless backend_secondary?
end

# sqeache still ultimately uses disk_log [1] for request logging, and if
# you change the log file sizing in the configuration **without also
# issuing a call to disk_log:change_size/2, sqeache won't start.
#
# Since we currently don't perform live upgrades, we can fake this by
# removing the *.siz files, which is where disk_log looks to determine
# what size the log files should be in the first place.  If they're
# not there, then we just use whatever size is listed in the
# configuration.
#
# [1]: http://erlang.org/doc/man/disk_log.html
execute "remove_sqeache_siz_files" do
  command "rm -f *.siz"
  cwd node['private_chef']['sqeache']['log_directory']
  action :nothing
end

link "/opt/opscode/embedded/service/sqeache/sys.config" do
  to sqeache_config
end

component_runit_service "sqeache"
