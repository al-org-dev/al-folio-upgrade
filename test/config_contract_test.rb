# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "stringio"

class ConfigContractTest < Minitest::Test
  FakeSpec = Struct.new(:name, :version, :full_gem_path)

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
          plugins:
            - al_folio_core
            - al_icons
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
      refute_includes ids, "missing_al_icons_plugin"
    end
  end

  def test_check_config_contract_warns_when_al_icons_plugin_missing
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "_config.yml"),
        <<~YAML
          plugins:
            - al_folio_core
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

      assert_includes ids, "missing_al_icons_plugin"
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

      distill_findings = findings.select { |finding| finding.id == "distill_remote_loader_enabled" }
      refute_empty distill_findings
      assert_includes distill_findings.map(&:file), "assets/js/distillpub/transforms.v2.js"
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

  def test_check_plugin_owned_local_assets_flags_runtime_assets_and_legacy_plugins
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "_plugins"))
      File.write(File.join(dir, "_plugins/external-posts.rb"), "noop")
      File.write(File.join(dir, "_plugins/google-scholar-citations.rb"), "noop")
      File.write(File.join(dir, "_plugins/hide-custom-bibtex.rb"), "noop")
      FileUtils.mkdir_p(File.join(dir, "assets/js/distillpub"))
      File.write(File.join(dir, "assets/js/distillpub/transforms.v2.js"), "noop")
      FileUtils.mkdir_p(File.join(dir, "assets/js/search"))
      File.write(File.join(dir, "assets/js/search/ninja-keys.min.js"), "noop")
      FileUtils.mkdir_p(File.join(dir, "assets/fonts"))
      File.write(File.join(dir, "assets/fonts/academicons.woff"), "noop")

      cli = AlFolioUpgrade::CLI.new(root: dir)
      findings = []
      cli.send(:check_plugin_owned_local_assets, findings)

      ids = findings.map(&:id)
      files = findings.map(&:file)
      assert_equal Array.new(6, "plugin_owned_local_asset"), ids.sort
      assert_includes files, "_plugins/external-posts.rb"
      assert_includes files, "_plugins/google-scholar-citations.rb"
      assert_includes files, "_plugins/hide-custom-bibtex.rb"
      assert_includes files, "assets/js/distillpub/transforms.v2.js"
      assert_includes files, "assets/js/search/ninja-keys.min.js"
      assert_includes files, "assets/fonts/academicons.woff"
    end
  end

  def test_local_override_results_classify_identical_override
    Dir.mktmpdir do |dir|
      gem_dir = File.join(dir, "gem")
      site_dir = File.join(dir, "site")
      FileUtils.mkdir_p(File.join(gem_dir, "_includes"))
      FileUtils.mkdir_p(File.join(site_dir, "_includes"))
      File.write(File.join(gem_dir, "_includes", "head.liquid"), "same\n")
      File.write(File.join(site_dir, "_includes", "head.liquid"), "same\n")

      cli = override_cli(site_dir, gem_dir)
      results = cli.send(:local_override_results)

      assert_equal 1, results.length
      assert_equal "_includes/head.liquid", results.first.local_path
      assert_equal :identical, results.first.status
      assert_equal "al_folio_core", results.first.owner
    end
  end

  def test_local_override_results_map_plugin_templates_to_local_includes
    Dir.mktmpdir do |dir|
      gem_dir = File.join(dir, "gem")
      site_dir = File.join(dir, "site")
      FileUtils.mkdir_p(File.join(gem_dir, "templates", "cv"))
      FileUtils.mkdir_p(File.join(site_dir, "_includes", "cv"))
      File.write(File.join(gem_dir, "templates", "cv", "render.liquid"), "upstream\n")
      File.write(File.join(site_dir, "_includes", "cv", "render.liquid"), "local\n")

      cli = override_cli(site_dir, gem_dir, owner: "al_folio_cv")
      results = cli.send(:local_override_results)

      assert_equal 1, results.length
      assert_equal "_includes/cv/render.liquid", results.first.local_path
      assert_equal "templates/cv/render.liquid", results.first.plugin_path
      assert_equal :unacknowledged, results.first.status
    end
  end

  def test_acknowledged_override_becomes_stale_when_upstream_changes
    Dir.mktmpdir do |dir|
      gem_dir = File.join(dir, "gem")
      site_dir = File.join(dir, "site")
      FileUtils.mkdir_p(File.join(gem_dir, "_layouts"))
      FileUtils.mkdir_p(File.join(site_dir, "_layouts"))
      File.write(File.join(gem_dir, "_layouts", "post.liquid"), "upstream v1\n")
      File.write(File.join(site_dir, "_layouts", "post.liquid"), "local custom\n")

      cli = override_cli(site_dir, gem_dir)
      assert_equal 0, cli.send(:acknowledge_overrides, :all)
      assert File.file?(File.join(site_dir, AlFolioUpgrade::CLI::OVERRIDE_ACK_PATH))

      File.write(File.join(gem_dir, "_layouts", "post.liquid"), "upstream v2\n")
      stale = cli.send(:local_override_results).first

      assert_equal :stale, stale.status
    end
  end

  def test_check_local_override_drift_warns_for_stale_override
    Dir.mktmpdir do |dir|
      gem_dir = File.join(dir, "gem")
      site_dir = File.join(dir, "site")
      FileUtils.mkdir_p(File.join(gem_dir, "_includes"))
      FileUtils.mkdir_p(File.join(site_dir, "_includes"))
      File.write(File.join(gem_dir, "_includes", "scripts.liquid"), "upstream v1\n")
      File.write(File.join(site_dir, "_includes", "scripts.liquid"), "local custom\n")

      cli = override_cli(site_dir, gem_dir)
      cli.send(:acknowledge_overrides, :all)
      File.write(File.join(gem_dir, "_includes", "scripts.liquid"), "upstream v2\n")

      findings = []
      cli.send(:check_local_override_drift, findings)

      assert_includes findings.map(&:id), "local_override_upstream_changed"
      assert_equal "_includes/scripts.liquid", findings.first.file
    end
  end

  private

  def override_cli(site_dir, gem_dir, owner: "al_folio_core")
    cli = AlFolioUpgrade::CLI.new(root: site_dir, stdout: StringIO.new, stderr: StringIO.new)
    spec = FakeSpec.new(owner, Gem::Version.new("1.0.9"), gem_dir)
    cli.define_singleton_method(:al_folio_plugin_specs) { [spec] }
    cli
  end
end
