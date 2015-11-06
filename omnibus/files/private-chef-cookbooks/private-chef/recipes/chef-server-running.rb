
file "/etc/opscode/chef-server-running.json" do
  owner OmnibusHelper.new(node).ownership['owner']
  group "root"
  mode "0600"
# TODO so some magic to just determine that if we're doing a one-off runlist
  #   only update the parts of the private_chef hash that are associated with that service?
  #   Otherwise we're going to have to pull in 3-4 more recipes just becuse of the magic configuration they
  #   do outside of the configure recipe.
  #
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
