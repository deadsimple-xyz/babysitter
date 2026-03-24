module Babysitter
  class Compliance
    Violation = Struct.new(:role, :path, :rule, :message, keyword_init: true)

    def initialize(rules:)
      @rules = rules
      @violations = []
    end

    attr_reader :violations

    def check_file_write(role:, path:)
      role = role.to_s

      if @rules.cannot_touch?(role, path)
        violation = Violation.new(
          role: role,
          path: path,
          rule: "cannot_touch",
          message: "#{role} agent cannot write to #{path} — file is owned by another role"
        )
        @violations << violation
        return violation.message
      end

      nil
    end

    def check_tool_use(role:, tool_name:, input:)
      role = role.to_s

      # Check file writes via Edit/Write tools
      if %w[Edit Write].include?(tool_name)
        file_path = input["file_path"] || input["path"]
        return check_file_write(role: role, path: file_path) if file_path
      end

      # Check Bash commands that write files
      if tool_name == "Bash"
        command = input["command"] || ""
        written_files = extract_write_targets(command)
        written_files.each do |file|
          result = check_file_write(role: role, path: file)
          return result if result
        end
      end

      nil
    end

    def violation_count
      @violations.size
    end

    private

    def extract_write_targets(command)
      targets = []

      # Redirect targets: > file, >> file
      command.scan(/>{1,2}\s*(\S+)/).each { |m| targets << m[0] }

      # tee command
      command.scan(/tee\s+(?:-a\s+)?(\S+)/).each { |m| targets << m[0] }

      # sed -i
      command.scan(/sed\s+-i[^\s]*\s+.*?\s+(\S+)$/).each { |m| targets << m[0] }

      targets
    end
  end
end
