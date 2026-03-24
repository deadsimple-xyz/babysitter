require "yaml"

module Babysitter
  class Rules
    def initialize(rules_dir: nil)
      @rules_dir = rules_dir || File.expand_path("../../rules", __FILE__)
      @global = load_yaml("global.yml")
      @per_role = {}
    end

    def for_role(role)
      role = role.to_s
      @per_role[role] ||= load_yaml("#{role}.yml")
    end

    def file_boundaries(role)
      role = role.to_s
      @global.dig("file_boundaries", role) || {}
    end

    def owns?(role, path)
      boundaries = file_boundaries(role)
      patterns = boundaries["owns"] || []
      patterns.any? { |pat| File.fnmatch?(pat, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) }
    end

    def cannot_touch?(role, path)
      boundaries = file_boundaries(role)
      patterns = boundaries["cannot_touch"] || []
      patterns.any? { |pat| File.fnmatch?(pat, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) }
    end

    def system_prompt(role)
      role_rules = for_role(role)
      role_rules["system_prompt"]
    end

    private

    def load_yaml(filename)
      path = File.join(@rules_dir, filename)
      return {} unless File.exist?(path)

      YAML.safe_load(File.read(path)) || {}
    end
  end
end
