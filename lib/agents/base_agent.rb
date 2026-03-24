require "json"
require "open3"

module Babysitter
  module Agents
    class BaseAgent
      attr_reader :role, :pid, :status, :last_activity_at, :output_lines

      def initialize(role:, working_dir:, system_prompt:, mcp_config_path: nil)
        @role = role.to_s
        @working_dir = working_dir
        @system_prompt = system_prompt
        @mcp_config_path = mcp_config_path
        @status = :idle
        @last_activity_at = Time.now
        @output_lines = []
        @callbacks = Hash.new { |h, k| h[k] = [] }
        @stdin = nil
        @stdout_thread = nil
        @pid = nil
      end

      def on(event, &block)
        @callbacks[event] << block
        self
      end

      def start(prompt)
        @status = :running
        @last_activity_at = Time.now

        cmd = build_command(prompt)
        @stdin, stdout, @wait_thread = Open3.popen2e(*cmd, chdir: @working_dir)
        @pid = @wait_thread.pid

        @stdout_thread = Thread.new { read_stream(stdout) }

        emit(:started, pid: @pid, role: @role)
        self
      end

      def stop
        return unless @pid
        @status = :stopping
        Process.kill("TERM", @pid)
        @wait_thread&.join(5)
        Process.kill("KILL", @pid) rescue nil
        @status = :stopped
        emit(:stopped, pid: @pid, role: @role)
      end

      def wait
        @stdout_thread&.join
        @wait_thread&.join
        exit_status = @wait_thread&.value
        @status = :finished
        emit(:finished, exit_status: exit_status&.exitstatus, role: @role)
        exit_status&.exitstatus
      end

      def running?
        @status == :running
      end

      def full_output
        @output_lines.join("\n")
      end

      private

      def build_command(prompt)
        cmd = ["claude"]
        cmd += ["--print"]
        cmd += ["--output-format", "stream-json"]
        cmd += ["--system-prompt", @system_prompt]
        if @mcp_config_path
          cmd += ["--mcp-config", @mcp_config_path]
          cmd += ["--permission-prompt-tool", "mcp__babysitter__gate"]
        end
        cmd += [prompt]
        cmd
      end

      def read_stream(io)
        io.each_line do |line|
          line = line.strip
          next if line.empty?
          @last_activity_at = Time.now

          event = parse_event(line)
          next unless event
          handle_event(event)
        end
      rescue IOError, Errno::EIO
        # stream closed
      ensure
        @status = :finished unless @status == :stopped
      end

      def parse_event(line)
        JSON.parse(line)
      rescue JSON::ParserError
        emit(:raw_output, line: line)
        nil
      end

      def handle_event(event)
        type = event["type"]
        case type
        when "assistant"
          text = extract_text(event)
          if text
            @output_lines << text
            emit(:assistant_message, text: text, event: event, role: @role)
          end
        when "tool_use"
          emit(:tool_use, tool: event["name"], input: event["input"], event: event, role: @role)
        when "tool_result"
          emit(:tool_result, tool: event["name"], output: event["output"], event: event, role: @role)
        when "result"
          emit(:result, result: event, event: event, role: @role)
        when "error"
          emit(:error, message: event["error"], event: event, role: @role)
        end
        emit(:any_event, event: event)
      end

      def extract_text(event)
        content = event["message"]&.dig("content")
        return nil unless content.is_a?(Array)
        content.select { |c| c["type"] == "text" }.map { |c| c["text"] }.join
      end

      def emit(event, **data)
        @callbacks[event].each { |cb| cb.call(data) }
      end
    end
  end
end
