# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class ConfigContractTest < Minitest::Test
  def test_core_override_contract_no_longer_marks_distill_runtime_as_core_owned
    core_override_files = AlFolioUpgrade::CLI::CORE_OVERRIDE_FILES

    refute_includes core_override_files, "_includes/distill_scripts.liquid"
    refute_includes core_override_files, "assets/js/distillpub/overrides.js"
    refute_includes core_override_files, "assets/js/distillpub/transforms.v2.js"
    assert_includes core_override_files, "_layouts/distill.liquid"
  end

  def test_check_config_contract_requires_nested_tailwind_and_distill
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "_config.yml"),
        <<~YAML
          tailwind:
            version: 0
          distill:
            engine: legacy
          al_folio:
            api_version: 1
            style_engine: tailwind
        YAML
      )

      cli = AlFolioUpgrade::CLI.new(root: dir)
      findings = []
      cli.send(:check_config_contract, findings)
      ids = findings.map(&:id)

      assert_includes ids, "missing_tailwind_namespace"
      assert_includes ids, "missing_distill_namespace"
    end
  end

  def test_ensure_tailwind_namespace_inserts_under_al_folio
    cli = AlFolioUpgrade::CLI.new(root: Dir.pwd)
    content = <<~YAML
      al_folio:
        api_version: 1
        style_engine: tailwind
    YAML

    updated = cli.send(:ensure_tailwind_namespace, content)
    assert_includes updated, "al_folio:\n  tailwind:\n    version: 4.1.18"
    refute_match(/^tailwind:\s*$/, updated)
  end

  def test_check_config_contract_accepts_date_scalars
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "_config.yml"),
        <<~YAML
          launch_date: 2026-01-01
          al_folio:
            api_version: 1
            style_engine: tailwind
            tailwind:
              version: 4.1.18
              preflight: false
              css_entry: assets/tailwind/app.css
            distill:
              engine: distillpub-template
              source: al-org-dev/distill-template#al-folio
              allow_remote_loader: false
        YAML
      )

      cli = AlFolioUpgrade::CLI.new(root: dir)
      findings = []
      cli.send(:check_config_contract, findings)
      ids = findings.map(&:id)

      refute_includes ids, "invalid_config_yaml"
    end
  end

  def test_check_distill_runtime_flags_remote_loader_when_disallowed
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets/js/distillpub"))
      File.write(
        File.join(dir, "assets/js/distillpub/transforms.v2.js"),
        "load('https://distill.pub/template.v2.js');\n"
      )
      File.write(
        File.join(dir, "_config.yml"),
        <<~YAML
          al_folio:
            distill:
              allow_remote_loader: false
        YAML
      )

      cli = AlFolioUpgrade::CLI.new(root: dir)
      findings = []
      cli.send(:check_distill_runtime, findings)

      assert_equal 1, findings.count
      assert_equal "distill_remote_loader_enabled", findings.first.id
      assert_equal "assets/js/distillpub/transforms.v2.js", findings.first.file
    end
  end

  def test_check_distill_runtime_skips_when_allow_remote_loader_enabled
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets/js/distillpub"))
      File.write(
        File.join(dir, "assets/js/distillpub/transforms.v2.js"),
        "load('https://distill.pub/template.v2.js');\n"
      )
      File.write(
        File.join(dir, "_config.yml"),
        <<~YAML
          al_folio:
            distill:
              allow_remote_loader: true
        YAML
      )

      cli = AlFolioUpgrade::CLI.new(root: dir)
      findings = []
      cli.send(:check_distill_runtime, findings)

      assert_equal 0, findings.count
    end
  end
end
