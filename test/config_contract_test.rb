# frozen_string_literal: true

require_relative "test_helper"

class ConfigContractTest < Minitest::Test
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
end
