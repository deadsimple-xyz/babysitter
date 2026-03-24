require "json"
require "fileutils"
require_relative "agents/base_agent"
require_relative "brain"
require_relative "prompts"
require_relative "gate"
require_relative "compliance"
require_relative "rules"

module Babysitter
  class Supervisor
    POLL_INTERVAL = 2
    MAX_STEPS = 10
    MAX_DEV_PASSES = 5

    def initialize(working_dir:, prompt:)
      @working_dir = File.expand_path(working_dir)
      @prompt = prompt
      @babysitter_dir = File.expand_path("..", __dir__)

      @data_dir = File.join(ENV["XDG_DATA_HOME"] || File.expand_path("~/.local/share"), "babysitter")
      @session_dir = File.join(@data_dir, "sessions", "session-#{Time.now.strftime('%Y%m%d-%H%M%S')}")
      @brain = Brain.new(session_dir: @session_dir)
      @rules = Rules.new
      @compliance = Compliance.new(rules: @rules)
      @gate = Gate.new(compliance: @compliance)
      @step = 0
      @dev_passes = 0
    end

    def run
      log "Babysitter starting"
      log "  workdir: #{@working_dir}"
      log "  session: #{@session_dir}"
      log "  prompt:  #{@prompt}"
      log ""

      # Brain analyzes the task
      log "Brain analyzing task..."
      hats_state = read_hats_state
      plan = @brain.analyze_task(prompt: @prompt, workdir: @working_dir, hats_state: hats_state)

      log "Plan: #{(plan['role_sequence'] || []).join(' -> ')}"
      log "Success: #{(plan['success_criteria'] || []).join('; ')}"
      log ""

      current_role = (plan["role_sequence"] || ["manager"]).first
      current_prompt = plan["first_role_prompt"] || @prompt

      loop do
        @step += 1

        if @step > MAX_STEPS
          log "!!! Hit max steps (#{MAX_STEPS}). Stopping."
          break
        end

        log "=== Step #{@step}: #{current_role.upcase} ==="

        # One clean pass
        output, exit_code = run_role(current_role, current_prompt)

        # Babysitter runs tests after developer
        test_results = nil
        if current_role == "developer"
          @dev_passes += 1
          test_results = run_tests
          log "Tests: #{test_results[:summary]}"
        end

        # Brain evaluates
        log "Brain evaluating..."
        review = @brain.evaluate_role(
          role: current_role,
          output: output,
          exit_code: exit_code,
          test_results: test_results,
          step: @step
        )

        verdict = review["verdict"] || "stop"
        log "Verdict: #{verdict} — #{review['verdict_reason']}"

        if review["violations"]&.any?
          log "Violations: #{review['violations'].join('; ')}"
        end

        if verdict == "stop"
          log "\n!!! STOPPED: #{review['verdict_reason']}"
          print_summary
          return false
        end

        next_role = review["next_role"]

        if next_role == "done"
          log "\n=== DONE ==="
          print_summary
          return true
        end

        if next_role == "developer" && @dev_passes >= MAX_DEV_PASSES
          log "!!! Developer had #{MAX_DEV_PASSES} passes. Stopping."
          print_summary
          return false
        end

        if next_role.nil? || next_role == "stop"
          log "Brain says stop."
          print_summary
          return false
        end

        current_role = next_role
        current_prompt = review["next_role_prompt"] || build_default_prompt(current_role)
        log ""
      end
    end

    private

    def run_role(role, prompt)
      mcp_config = write_mcp_config(role)
      system_prompt = Prompts.for(role)

      agent = Agents::BaseAgent.new(
        role: role,
        working_dir: @working_dir,
        system_prompt: system_prompt,
        mcp_config_path: mcp_config
      )

      agent.on(:assistant_message) do |data|
        text = (data[:text] || "").gsub(/\s+/, " ").slice(0, 200)
        log "  [#{role}] #{text}"
      end

      agent.on(:tool_use) do |data|
        log "  [#{role}] tool: #{data[:tool]}"
      end

      agent.on(:error) do |data|
        log "  [#{role}] ERROR: #{data[:message]}"
      end

      agent.start(prompt)

      while agent.running?
        sleep POLL_INTERVAL
      end

      exit_code = agent.wait
      output = agent.full_output

      FileUtils.mkdir_p(@session_dir)
      File.write(File.join(@session_dir, "step#{@step}_#{role}_output.txt"), output)

      [output, exit_code]
    end

    def run_tests
      runner = File.join(@working_dir, ".hats", "qa", "run-tests.sh")

      unless File.exist?(runner)
        return { ran: false, passed: false, summary: "No run-tests.sh found", output: "" }
      end

      log "Running tests..."
      output = `cd #{@working_dir} && bash .hats/qa/run-tests.sh 2>&1`
      passed = $?.success?

      File.write(File.join(@session_dir, "step#{@step}_test_output.txt"), output)

      # Update qa-report so next developer pass sees fresh results
      report_path = File.join(@working_dir, ".hats", "shared", "qa-report.md")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, <<~REPORT)
        # QA Report (babysitter step #{@step})

        ## Results
        #{passed ? "All tests passing." : "Tests failing."}

        ## Output
        ```
        #{output.lines.last(50).join}
        ```
      REPORT

      { ran: true, passed: passed, summary: passed ? "ALL PASS" : "FAILING", output: output }
    end

    def build_default_prompt(role)
      case role
      when "manager"   then "Review the current project status and update specs as needed."
      when "designer"  then "Read the specs and create or update screen descriptions."
      when "cto"       then "Read the specs and designs, decide on the technology stack."
      when "qa"        then "Read the specs and write automated tests. Run them once and write the report."
      when "developer" then "Read .hats/shared/qa-report.md for test failures. Write code to fix them. Do NOT run tests."
      else "Continue."
      end
    end

    def print_summary
      log "Session: #{@session_dir}"
      log "Steps: #{@step}, Developer passes: #{@dev_passes}/#{MAX_DEV_PASSES}"
    end

    def read_hats_state
      parts = []

      %w[manager designer cto qa shared].each do |dir|
        full = File.join(@working_dir, ".hats", dir)
        next unless File.directory?(full)
        files = Dir.glob(File.join(full, "*")).map { |f| File.basename(f) }
        parts << ".hats/#{dir}/: #{files.join(', ')}" if files.any?
      end

      status_path = File.join(@working_dir, ".hats", "status.json")
      parts << "status.json: #{File.read(status_path)}" if File.exist?(status_path)

      report = File.join(@working_dir, ".hats", "shared", "qa-report.md")
      parts << "qa-report.md:\n#{File.read(report)[-500..]}" if File.exist?(report)

      parts.empty? ? "No .hats/ directory found. Fresh project." : parts.join("\n")
    end

    def write_mcp_config(role)
      config_dir = File.join(@session_dir, "mcp")
      FileUtils.mkdir_p(config_dir)
      config_path = File.join(config_dir, "mcp-config-#{role}.json")

      mcp_bin = File.join(@babysitter_dir, "bin", "babysitter-mcp")
      config = {
        mcpServers: {
          babysitter: {
            command: "ruby",
            args: [mcp_bin],
            env: { "BABYSITTER_AGENT_ROLE" => role }
          }
        }
      }

      File.write(config_path, config.to_json)
      config_path
    end

    def log(message)
      timestamp = Time.now.strftime("%H:%M:%S")
      line = "[#{timestamp}] #{message}"
      $stderr.puts line

      if @session_dir
        FileUtils.mkdir_p(@session_dir)
        File.open(File.join(@session_dir, "log.txt"), "a") { |f| f.puts line }
      end
    end
  end
end
