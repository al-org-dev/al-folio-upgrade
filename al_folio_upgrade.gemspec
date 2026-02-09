# frozen_string_literal: true

require_relative "lib/al_folio_upgrade/version"

Gem::Specification.new do |spec|
  spec.name = "al_folio_upgrade"
  spec.version = AlFolioUpgrade::VERSION
  spec.authors = ["al-folio maintainers"]
  spec.email = ["maintainers@al-folio.dev"]

  spec.summary = "Upgrade tooling for al-folio v1.x"
  spec.description = "Provides audit, report, and safe codemod commands for al-folio upgrades."
  spec.homepage = "https://github.com/al-org-dev/al-folio-upgrade"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
  }

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["al-folio"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 3.9", "< 5.0"
  spec.add_dependency "liquid", ">= 4.0", "< 6.0"
  spec.add_dependency "al_folio_core", ">= 0.1.0"

  spec.add_development_dependency "bundler", ">= 2.0", "< 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
