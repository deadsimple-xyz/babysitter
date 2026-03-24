require "json"

module Babysitter
  class MCPServer
    PROTOCOL_VERSION = "2024-11-05"

    def initialize(gate:, agent_role: nil)
      @gate = gate
      @agent_role = agent_role || ENV["BABYSITTER_AGENT_ROLE"] || "unknown"
      @initialized = false
    end

    def run(input: $stdin, output: $stdout)
      output.sync = true
      $stderr.puts "[babysitter-mcp] starting for role=#{@agent_role}"

      input.each_line do |line|
        line = line.strip
        next if line.empty?

        request = parse_request(line)
        next unless request

        response = handle_request(request)
        if response
          output.puts(response.to_json)
          output.flush
        end
      end
    rescue IOError, Errno::EPIPE
      $stderr.puts "[babysitter-mcp] stream closed"
    end

    private

    def parse_request(line)
      JSON.parse(line)
    rescue JSON::ParserError => e
      $stderr.puts "[babysitter-mcp] invalid JSON: #{e.message}"
      nil
    end

    def handle_request(request)
      method = request["method"]
      id = request["id"]

      case method
      when "initialize"
        handle_initialize(id, request["params"])
      when "notifications/initialized"
        # Client ack — no response needed
        nil
      when "tools/list"
        handle_tools_list(id)
      when "tools/call"
        handle_tools_call(id, request["params"])
      when "ping"
        jsonrpc_result(id, {})
      else
        if id
          jsonrpc_error(id, -32601, "Method not found: #{method}")
        end
      end
    end

    def handle_initialize(id, params)
      @initialized = true
      jsonrpc_result(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "babysitter", version: "0.1.0" }
      })
    end

    def handle_tools_list(id)
      jsonrpc_result(id, {
        tools: [gate_tool_schema]
      })
    end

    def handle_tools_call(id, params)
      tool_name = params&.dig("name")
      arguments = params&.dig("arguments") || {}

      case tool_name
      when "gate"
        handle_gate(id, arguments)
      else
        jsonrpc_error(id, -32602, "Unknown tool: #{tool_name}")
      end
    end

    def handle_gate(id, arguments)
      command = arguments["command"] || ""
      file_path = arguments["file_path"]
      tool_name = arguments["tool_name"]

      decision = @gate.evaluate(
        command: command,
        agent_role: @agent_role,
        file_path: file_path,
        tool_name: tool_name
      )

      $stderr.puts "[babysitter-gate] role=#{@agent_role} command=#{command.inspect} => #{decision.approved ? 'ALLOW' : 'DENY'}: #{decision.reason}"

      jsonrpc_result(id, {
        content: [
          {
            type: "text",
            text: { approved: decision.approved, reason: decision.reason }.to_json
          }
        ]
      })
    end

    def gate_tool_schema
      {
        name: "gate",
        description: "Permission gate — evaluates whether a command or file write should be allowed for this agent's role. Called by Claude Code before executing any permission-requiring action.",
        inputSchema: {
          type: "object",
          properties: {
            command: {
              type: "string",
              description: "The shell command being evaluated"
            },
            file_path: {
              type: "string",
              description: "The file path being written to (if applicable)"
            },
            tool_name: {
              type: "string",
              description: "The tool being used (Bash, Write, Edit, etc.)"
            }
          },
          required: ["command"]
        }
      }
    end

    def jsonrpc_result(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def jsonrpc_error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
  end
end
