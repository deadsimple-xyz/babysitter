require "yaml"

module Babysitter
  class Gate
    Decision = Struct.new(:approved, :reason, keyword_init: true)

    def initialize(rules_path: nil, compliance: nil)
      @rules_path = rules_path || File.expand_path("../../rules/gate.yml", __FILE__)
      @rules = YAML.safe_load(File.read(@rules_path))
      @compliance = compliance
      @log = []
    end

    attr_reader :log

    def evaluate(command:, agent_role:, file_path: nil, tool_name: nil)
      record = { time: Time.now, agent_role: agent_role, command: command, file_path: file_path, tool_name: tool_name }

      # Check file compliance first (if a file write)
      if file_path && @compliance
        violation = @compliance.check_file_write(role: agent_role, path: file_path)
        if violation
          record[:decision] = :deny
          record[:reason] = violation
          @log << record
          return Decision.new(approved: false, reason: violation)
        end
      end

      decision = evaluate_command(command)
      record[:decision] = decision.approved ? :allow : (decision.reason.include?("ask") ? :ask : :deny)
      record[:reason] = decision.reason
      @log << record
      decision
    end

    private

    def evaluate_command(command)
      return Decision.new(approved: true, reason: "empty command") if command.nil? || command.strip.empty?

      # Check deny rules first — deny takes priority
      (@rules["deny"] || []).each do |rule|
        if command.match?(Regexp.new(rule["pattern"], Regexp::IGNORECASE))
          return Decision.new(approved: false, reason: "DENIED: #{rule['reason']}")
        end
      end

      # Check allow rules
      (@rules["allow"] || []).each do |rule|
        if command.match?(Regexp.new(rule["pattern"]))
          return Decision.new(approved: true, reason: "ALLOWED: #{rule['reason']}")
        end
      end

      # Default: ask the user
      Decision.new(approved: false, reason: "Command not in allow list — requires user approval (ask)")
    end
  end
end
