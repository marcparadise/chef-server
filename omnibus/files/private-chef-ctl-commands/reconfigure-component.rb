
add_command_under_category "reconfigure-component",  "general", "For development use only: Reconfigure a specific service within Chef Server.", 2 do
  status = run_chef("#{base_path}/embedded/cookbooks/dna.json", "-l fatal -o recipe[private-chef::config],recipe[enterprise::runit],recipe[private-chef::#{ARGV.last}]" )
  exit! status.success? ? 0 : 1
end
