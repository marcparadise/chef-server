require "tempfile"
require "mixlib/shellout"

class TemplateVerifier

  def verify(node, path)
    #TODO - maybe a better way to capture this path?
    status = do_verify("/opt/opscode/embedded/cookbooks/private-chef/libraries/template-validators", node, path)
    if status.exitstatus == 0
      true
    else
      error_line, error_message = status.stderr.split(":", 2)
      error_line = (error_line.to_i - 1) # we're going zero based
      lines = File.readlines(path)
      # Preserve file contents for inspection
      tempfile = Tempfile.new(File.basename(path))
      tpath = tempfile.path
      tempfile.close!
      File.open(tpath,"w") do |out|
        lines.each do |l|
          out.write l
        end
      end

      #
      message = <<EOM
***********************************************************************
Template validation failed for #{tpath}.

  #{message}

Here's what was reported:

EOM
      if error_line == -1
        message << "     #{error_message}"
      else

        start_line = [0, error_line - 5].max
        end_line = [error_line + 5, lines.length].min
        x = start_line
        while x < end_line
          if x == error_line
            message << " ERR *****> Failing Line Follows:\n"
            message << " ERR #{(x + 1).to_s.rjust(5, '*')}> #{lines[x]}"
            message << " ERR *****> ^ --- #{error_message.chomp} ---^ \n"
          else
            message << "#{(x + 1).to_s.rjust(10, ' ')} > #{lines[x]}"
          end

          x += 1
        end
        message << <<EOM

You can find a copy of this file at #{tpath}
***********************************************************************
EOM
      end

      Chef::Log.fatal message
      false
    end
  end
end


class YAMLTemplateVerifier < TemplateVerifier
  def do_verify(validator_base, node, path)
    cmd = Mixlib::ShellOut.new("/opt/opscode/embedded/bin/ruby #{validator_base}/yaml-validator #{path}")
    cmd.run_command
  end
end
class ErlangTemplateVerifier < TemplateVerifier
  def do_verify(validator_base, node, path)
    cmd = Mixlib::ShellOut.new("/opt/opscode/embedded/bin/escript #{validator_base}/erlang-validator #{path}")
    cmd.run_command
  end
end
