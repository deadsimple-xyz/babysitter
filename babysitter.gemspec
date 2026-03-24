Gem::Specification.new do |s|
  s.name        = "babysitter"
  s.version     = "0.1.0"
  s.summary     = "Supervisor process for Hats agents"
  s.description = "Keeps Hats agents on-role, unstuck, and gates every command they try to run."
  s.authors     = ["releu"]
  s.license     = "MIT"

  s.required_ruby_version = ">= 2.6"

  s.files       = Dir["lib/**/*.rb", "bin/*", "rules/*.yml", "BABYSITTER.md"]
  s.bindir      = "bin"
  s.executables = ["babysitter"]

  s.add_dependency "json"
end
