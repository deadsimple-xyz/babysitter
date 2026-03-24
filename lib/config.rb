require "json"
require "fileutils"

module Babysitter
  class Config
    CONFIG_DIR = File.expand_path("~/.babysitter")
    KEY_FILE = File.join(CONFIG_DIR, "key.json")

    def self.api_key
      if File.exist?(KEY_FILE)
        data = JSON.parse(File.read(KEY_FILE))
        return data["api_key"] if data["api_key"] && !data["api_key"].empty?
      end

      nil
    end

    def self.api_key!
      key = api_key
      return key if key

      # Interactive prompt
      $stderr.puts "No API key found."
      $stderr.puts ""
      $stderr.puts "Babysitter needs an Anthropic API key for the Brain."
      $stderr.puts "Get one at: https://console.anthropic.com/settings/keys"
      $stderr.puts ""
      $stderr.print "Paste your API key: "
      key = $stdin.gets&.strip

      if key.nil? || key.empty?
        $stderr.puts "No key provided. Exiting."
        exit 1
      end

      save_api_key(key)
      $stderr.puts "Saved to #{KEY_FILE}"
      $stderr.puts ""
      key
    end

    def self.save_api_key(key)
      FileUtils.mkdir_p(CONFIG_DIR)
      File.write(KEY_FILE, JSON.pretty_generate({ api_key: key }))
      File.chmod(0600, KEY_FILE)
    end
  end
end
