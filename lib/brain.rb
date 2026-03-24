require "json"
require "net/http"
require "uri"
require "fileutils"

module Babysitter
  class Brain
    ROLES = %w[manager designer cto qa developer].freeze

    def initialize(session_dir:, model: "claude-sonnet-4-6", api_key: nil)
      @session_dir = session_dir
      @model = model
      @api_key = api_key || ENV["ANTHROPIC_API_KEY"]
      FileUtils.mkdir_p(@session_dir)
    end

    # Step 1: Understand the task, define success criteria, plan the role sequence
    def analyze_task(prompt:, workdir:, hats_state: nil)
      response = ask(<<~Q)
        You are a supervisor planning a development session.

        The user wants: #{prompt}
        Working directory: #{workdir}
        #{hats_state ? "Current project state:\n#{hats_state}" : ""}

        Analyze this and respond with JSON only:
        {
          "task_summary": "one paragraph — what needs to happen",
          "success_criteria": ["list of concrete, checkable outcomes"],
          "role_sequence": ["ordered list of roles to activate: manager|designer|cto|qa|developer"],
          "first_role_prompt": "the exact prompt to give the first role"
        }

        Rules for choosing roles:
        - manager: needed when specs (.feature files) must be created or updated
        - designer: needed when UI/UX decisions are missing
        - cto: needed when stack.md doesn't exist or tech decisions needed
        - qa: needed when tests must be written or updated
        - developer: needed when code must be implemented or fixed
        - Skip roles that aren't needed. If tests exist and code needs fixing, just run developer.
        - If unsure, start with manager — it reads status and decides.
      Q

      result = parse_json(response)
      write_file("task.md", <<~MD)
        # Task

        **Prompt:** #{prompt}
        **Working directory:** #{workdir}

        ## Summary
        #{result["task_summary"]}

        ## Success Criteria
        #{(result["success_criteria"] || []).map { |c| "- [ ] #{c}" }.join("\n")}

        ## Planned Role Sequence
        #{(result["role_sequence"] || []).map.with_index(1) { |r, i| "#{i}. #{r}" }.join("\n")}

        ## First Role Prompt
        #{result["first_role_prompt"]}
      MD

      result
    end

    # Step 2: After a role finishes, evaluate its output
    def evaluate_role(role:, output:, exit_code:, test_results: nil, step: nil)
      task_context = read_file("task.md")

      test_section = ""
      if test_results
        test_section = <<~T

          ## Test Results (run externally by babysitter)
          Ran: #{test_results[:ran]}
          Passed: #{test_results[:passed]}
          Summary: #{test_results[:summary]}
          Output (last 2000 chars):
          #{test_results[:output].to_s[-2000..]}
        T
      end

      response = ask(<<~Q)
        You are a supervisor reviewing an agent's work.

        ## Task Context
        #{task_context}

        ## Role: #{role}
        Exit code: #{exit_code}
        #{test_section}

        ## Agent Output (last 4000 chars)
        #{output.to_s[-4000..]}

        Evaluate and respond with JSON only:
        {
          "followed_rules": true|false,
          "violations": ["list of rule violations, empty if none"],
          "work_summary": "what the agent actually did",
          "issues": ["problems found, empty if none"],
          "verdict": "ok|warning|stop",
          "verdict_reason": "why this verdict",
          "next_role": "manager|designer|cto|qa|developer|done|stop",
          "next_role_prompt": "exact prompt for the next role — include specific failure details if sending back to developer. Empty if done/stop."
        }

        Important:
        - If tests pass → next_role should be "done"
        - If tests fail and developer just ran → next_role "developer" with failure details in the prompt
        - If agent went off-role or violated rules → verdict "stop"
        - The developer does NOT run tests — babysitter runs them. So don't penalize developer for not running tests.

        Rules for #{role}:
        #{role_rules(role)}

        verdict guide:
        - "ok": role did its job, proceed to next
        - "warning": minor issues but can continue
        - "stop": serious problem, must tell the user
      Q

      result = parse_json(response)
      write_file("#{role}_review.md", <<~MD)
        # #{role.capitalize} Review

        **Verdict:** #{result["verdict"]} — #{result["verdict_reason"]}
        **Exit code:** #{exit_code}

        ## What it did
        #{result["work_summary"]}

        ## Rule compliance
        Followed rules: #{result["followed_rules"]}
        #{(result["violations"] || []).empty? ? "No violations." : "Violations:\n" + result["violations"].map { |v| "- #{v}" }.join("\n")}

        ## Issues
        #{(result["issues"] || []).empty? ? "None." : result["issues"].map { |i| "- #{i}" }.join("\n")}

        ## Decision
        Next: #{result["next_role"]}
        #{result["next_role_prompt"]}
      MD

      result
    end

    # Read accumulated session state for context
    def session_summary
      files = Dir.glob(File.join(@session_dir, "*.md")).sort
      files.map { |f| File.read(f) }.join("\n\n---\n\n")
    end

    private

    def role_rules(role)
      case role
      when "manager"
        <<~R
          - Owns .feature files in .hats/manager/. Cannot write code or tests.
          - Should produce task breakdowns and specs.
          - Must write to .hats/shared/manager2team.md when done.
        R
      when "designer"
        <<~R
          - Owns .hats/designer/. Cannot write code or tests.
          - Should produce screen descriptions and wireframes.
          - Must write to .hats/shared/designer2team.md when done.
        R
      when "cto"
        <<~R
          - Owns .hats/shared/stack.md, setup.md, api.md. Cannot write code or tests.
          - Should make technology decisions.
          - Must write to .hats/shared/cto2team.md when done.
        R
      when "qa"
        <<~R
          - Owns .hats/qa/. Cannot write implementation code (lib/, app/, src/).
          - Should write tests from specs, not implementation.
          - Must create .hats/qa/run-tests.sh.
          - Must NOT copy or rewrite .feature files.
          - Must write to .hats/shared/qa2dev.md and qa-report.md when done.
        R
      when "developer"
        <<~R
          - Owns project source code (lib/, app/, src/). Cannot touch .hats/qa/.
          - Must NOT read test source files in .hats/qa/.
          - Implements code to make tests pass based on qa-report.md.
          - Must write to .hats/shared/dev2qa.md when done.
        R
      else
        "No specific rules."
      end
    end

    def ask(prompt)
      unless @api_key
        raise "ANTHROPIC_API_KEY required for babysitter brain"
      end

      uri = URI("https://api.anthropic.com/v1/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = @api_key
      request["anthropic-version"] = "2023-06-01"
      request.body = {
        model: @model,
        max_tokens: 1024,
        messages: [{ role: "user", content: prompt }]
      }.to_json

      response = http.request(request)

      unless response.code.to_i == 200
        raise "Brain API error #{response.code}: #{response.body}"
      end

      body = JSON.parse(response.body)
      body.dig("content", 0, "text") || ""
    end

    def parse_json(text)
      # Extract JSON from response — might be wrapped in ```json blocks
      json_str = text[/```json\s*\n?(.*?)\n?```/m, 1] || text[/\{.*\}/m]
      JSON.parse(json_str)
    rescue JSON::ParserError, TypeError => e
      $stderr.puts "[brain] Failed to parse response: #{e.message}"
      $stderr.puts "[brain] Raw: #{text}"
      { "verdict" => "stop", "verdict_reason" => "Brain could not parse its own response", "next_role" => "stop" }
    end

    def write_file(name, content)
      File.write(File.join(@session_dir, name), content)
    end

    def read_file(name)
      path = File.join(@session_dir, name)
      File.exist?(path) ? File.read(path) : ""
    end
  end
end
