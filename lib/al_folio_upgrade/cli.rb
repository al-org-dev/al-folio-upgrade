# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require "date"

begin
  require "al_folio_core"
rescue LoadError
  # Optional at runtime; fallback lookup paths are used if unavailable.
end

module AlFolioUpgrade
  class CLI
    REPORT_PATH = "al-folio-upgrade-report.md"

    Finding = Struct.new(:id, :severity, :message, :file, :line, :snippet, keyword_init: true)

    FILE_GLOBS = [
      "_config.yml",
      "_includes/**/*.{liquid,html}",
      "_layouts/**/*.{liquid,html}",
      "_pages/**/*.{md,markdown,liquid,html}",
      "_posts/**/*.{md,markdown,liquid,html}",
      "assets/js/**/*.js",
      "assets/css/**/*.css",
      "assets/tailwind/**/*.css",
    ].freeze

    IGNORE_PATH_PATTERNS = [
      /\/distillpub\//,
      /\/search\/ninja-footer\.min\.js$/,
      /\/bootstrap\.bundle\.min\.js$/,
      /\/bootstrap-toc\.min\.js$/,
      /\.min\.js$/,
      /\.map$/,
    ].freeze

    SAFE_REPLACEMENTS = [
      { from: /\bfont-weight-bold\b/, to: "font-bold" },
      { from: /\bfont-weight-medium\b/, to: "font-medium" },
      { from: /\bfont-weight-lighter\b/, to: "font-light" },
      { from: %r{https://distill\.pub/template\.v2\.js}, to: "/assets/js/distillpub/template.v2.js" },
      { from: %r{assets/tailwind/input\.css}, to: "assets/tailwind/app.css" },
    ].freeze

    CORE_OVERRIDE_FILES = %w[
      _includes/head.liquid
      _includes/scripts.liquid
      _layouts/default.liquid
      _layouts/post.liquid
      _layouts/page.liquid
      _layouts/distill.liquid
      assets/js/common.js
      assets/js/theme.js
      assets/js/tooltips-setup.js
      assets/tailwind/app.css
      tailwind.config.js
    ].freeze

    def initialize(root: Dir.pwd, stdout: $stdout, stderr: $stderr)
      @root = Pathname.new(root)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      return usage(1) if argv.empty?

      command = argv.shift
      unless command == "upgrade"
        @stderr.puts("Unsupported command: #{command}")
        return usage(1)
      end

      subcommand = argv.shift
      case subcommand
      when "audit"
        options = { fail_on_blocking: true }
        OptionParser.new do |opts|
          opts.on("--no-fail", "Do not fail even when blocking findings exist") do
            options[:fail_on_blocking] = false
          end
        end.parse!(argv)

        findings = audit
        write_report(findings)
        print_summary(findings)
        return 1 if options[:fail_on_blocking] && blocking?(findings)

        0
      when "apply"
        options = { safe: false }
        OptionParser.new do |opts|
          opts.on("--safe", "Apply only deterministic safe codemods") do
            options[:safe] = true
          end
        end.parse!(argv)

        unless options[:safe]
          @stderr.puts("Only --safe mode is supported in v1.x.")
          return 1
        end

        changed_files = apply_safe_codemods
        findings = audit
        write_report(findings)
        @stdout.puts("Applied safe codemods to #{changed_files} file(s).")
        print_summary(findings)
        0
      when "report"
        findings = audit
        write_report(findings)
        print_summary(findings)
        0
      else
        @stderr.puts("Unsupported subcommand: #{subcommand.inspect}")
        usage(1)
      end
    end

    private

    def usage(code)
      @stdout.puts("Usage: al-folio upgrade [audit|apply --safe|report] [--no-fail]")
      code
    end

    def blocking?(findings)
      findings.any? { |finding| finding.severity == :blocking }
    end

    def audit
      findings = []
      check_manifest_contract(findings)
      check_config_contract(findings)
      check_legacy_assets(findings)
      check_legacy_patterns(findings)
      check_distill_runtime(findings)
      check_core_override_drift(findings)
      findings
    end

    def check_manifest_contract(findings)
      manifests = manifest_paths
      if manifests.empty?
        findings << Finding.new(
          id: "missing_migration_manifests",
          severity: :warning,
          message: "No migration manifests found. Install/update `al_folio_core` to get release contracts.",
          file: "migrations/",
          line: 1,
          snippet: "Expected at least one `x.y.z_to_a.b.c.yml` manifest."
        )
      end
    end

    def check_config_contract(findings)
      config_path = @root.join("_config.yml")
      return unless config_path.file?

      content = config_path.read
      parsed = begin
        parse_yaml(content) || {}
      rescue StandardError => e
        findings << Finding.new(
          id: "invalid_config_yaml",
          severity: :blocking,
          message: "_config.yml could not be parsed: #{e.message}",
          file: "_config.yml",
          line: 1,
          snippet: "Fix YAML syntax before running upgrade codemods."
        )
        return
      end

      al_folio = parsed.is_a?(Hash) ? parsed["al_folio"] : nil
      unless al_folio.is_a?(Hash)
        findings << Finding.new(
          id: "missing_al_folio_namespace",
          severity: :blocking,
          message: "Missing `al_folio` config namespace required for v1.x.",
          file: "_config.yml",
          line: 1,
          snippet: "Add al_folio.api_version, style_engine, compat, and upgrade keys."
        )
        return
      end

      unless al_folio["style_engine"] == "tailwind"
        findings << Finding.new(
          id: "style_engine_not_tailwind",
          severity: :blocking,
          message: "`al_folio.style_engine` should be set to `tailwind` for v1.x.",
          file: "_config.yml",
          line: 1,
          snippet: "Set al_folio.style_engine: tailwind"
        )
      end

      unless al_folio["tailwind"].is_a?(Hash)
        findings << Finding.new(
          id: "missing_tailwind_namespace",
          severity: :warning,
          message: "Missing `al_folio.tailwind` namespace for v1 tailwind runtime contract.",
          file: "_config.yml",
          line: 1,
          snippet: "Add al_folio.tailwind.version/preflight/css_entry."
        )
      end

      unless al_folio["distill"].is_a?(Hash)
        findings << Finding.new(
          id: "missing_distill_namespace",
          severity: :warning,
          message: "Missing `al_folio.distill` namespace for Distill runtime contract.",
          file: "_config.yml",
          line: 1,
          snippet: "Add al_folio.distill.engine/source/allow_remote_loader."
        )
      end
    end

    def check_legacy_assets(findings)
      files = ["_includes/head.liquid", "_includes/scripts.liquid"]
      patterns = [
        /bootstrap\.min\.css/,
        /mdbootstrap|mdb\.min\.(?:css|js)/,
        /third_party_libraries\.jquery/,
        /bootstrap\.bundle\.min\.js/,
      ]

      files.each do |file|
        path = @root.join(file)
        next unless path.file?

        path.each_line.with_index(1) do |line, number|
          next unless patterns.any? { |pattern| line.match?(pattern) }

          findings << Finding.new(
            id: "legacy_bootstrap_runtime_asset",
            severity: :blocking,
            message: "Legacy Bootstrap/jQuery/MDB runtime assets are still referenced in core includes.",
            file: file,
            line: number,
            snippet: line.strip
          )
        end
      end
    end

    def check_legacy_patterns(findings)
      each_candidate_file do |relative, line, number|
        if line.match?(/data-toggle\s*=\s*["'](?:collapse|dropdown|tooltip|popover|table)["']/)
          findings << Finding.new(
            id: "legacy_data_toggle",
            severity: :warning,
            message: "Legacy Bootstrap `data-toggle` marker found.",
            file: relative,
            line: number,
            snippet: line.strip
          )
        end

        if line.match?(/\$\(|jQuery\b/)
          findings << Finding.new(
            id: "legacy_jquery_usage",
            severity: :warning,
            message: "jQuery usage found; migrate to vanilla JS APIs.",
            file: relative,
            line: number,
            snippet: line.strip
          )
        end
      end
    end

    def check_distill_runtime(findings)
      config_path = @root.join("_config.yml")
      allow_remote_loader = false
      if config_path.file?
        begin
          parsed = parse_yaml(config_path.read) || {}
          allow_remote_loader = parsed.dig("al_folio", "distill", "allow_remote_loader") == true
        rescue StandardError
          allow_remote_loader = false
        end
      end

      return if allow_remote_loader

      distill_runtime_paths.each do |transforms_path|
        report_file = if transforms_path.to_s.start_with?("#{@root}#{File::SEPARATOR}")
                        transforms_path.relative_path_from(@root).to_s
                      else
                        "al_folio_distill:#{transforms_path}"
                      end

        transforms_path.each_line.with_index(1) do |line, number|
          next unless line.match?(%r{https://distill\.pub/template\.v2\.js})

          findings << Finding.new(
            id: "distill_remote_loader_enabled",
            severity: :blocking,
            message: "Distill runtime still references remote template loader while allow_remote_loader is false.",
            file: report_file,
            line: number,
            snippet: line.strip
          )
        end
      end
    end

    def distill_runtime_paths
      paths = [@root.join("assets/js/distillpub/transforms.v2.js")]
      specs = []
      specs << Gem.loaded_specs["al_folio_distill"] if Gem.loaded_specs.key?("al_folio_distill")
      begin
        specs << Gem::Specification.find_by_name("al_folio_distill")
      rescue Gem::LoadError
        # Optional gem; ignore when not installed.
      end

      specs.compact.uniq(&:full_gem_path).each do |spec|
        paths << Pathname.new(File.join(spec.full_gem_path, "assets/js/distillpub/transforms.v2.js"))
      end
      paths.select(&:file?).uniq
    end

    def check_core_override_drift(findings)
      return unless using_core_theme?

      CORE_OVERRIDE_FILES.each do |relative|
        path = @root.join(relative)
        next unless path.file?

        findings << Finding.new(
          id: "core_override_drift",
          severity: :warning,
          message: "Local override shadows `al_folio_core` theme file and may need manual review during upgrades.",
          file: relative,
          line: 1,
          snippet: "Local override present."
        )
      end
    end

    def each_candidate_file
      FILE_GLOBS.each do |glob|
        Dir.glob(@root.join(glob)).sort.each do |path|
          next unless File.file?(path)
          next if ignored_path?(path)

          rel = Pathname.new(path).relative_path_from(@root).to_s
          File.foreach(path).with_index(1) do |line, number|
            yield rel, line, number
          end
        end
      end
    end

    def apply_safe_codemods
      changed_files = 0

      each_text_file do |path|
        original = File.read(path)
        updated = original.dup

        SAFE_REPLACEMENTS.each do |rule|
          updated = updated.gsub(rule[:from], rule[:to])
        end

        if Pathname.new(path).relative_path_from(@root).to_s == "_config.yml"
          updated = ensure_al_folio_namespace(updated)
        end

        next if updated == original

        File.write(path, updated)
        changed_files += 1
      end

      changed_files
    end

    def ensure_al_folio_namespace(content)
      if content.match?(/^al_folio:\s*$/)
        content = ensure_tailwind_namespace(content)
        content = ensure_distill_namespace(content)
        return content
      end

      block = <<~YAML

        al_folio:
          api_version: 1
          style_engine: tailwind
          tailwind:
            version: 4.1.18
            preflight: false
            css_entry: assets/tailwind/app.css
          distill:
            engine: distillpub-template
            source: alshedivat/distillpub-template#al-folio
            allow_remote_loader: true
          compat:
            bootstrap:
              enabled: false
              support_window: v1.0-v1.2
              deprecates_in: v1.3
              removed_in: v2.0
          upgrade:
            channel: stable
            auto_apply_safe_fixes: false
      YAML
      content + block
    end

    def ensure_tailwind_namespace(content)
      return content if nested_namespace_present?(content, "tailwind")

      insertion = [
        "  tailwind:",
        "    version: 4.1.18",
        "    preflight: false",
        "    css_entry: assets/tailwind/app.css",
      ].join("\n")
      content.sub(/^al_folio:\s*$/) { |match| "#{match}\n#{insertion}" }
    end

    def ensure_distill_namespace(content)
      return content if nested_namespace_present?(content, "distill")

      insertion = [
        "  distill:",
        "    engine: distillpub-template",
        "    source: alshedivat/distillpub-template#al-folio",
        "    allow_remote_loader: true",
      ].join("\n")
      content.sub(/^al_folio:\s*$/) { |match| "#{match}\n#{insertion}" }
    end

    def nested_namespace_present?(content, key)
      parsed = parse_yaml(content) || {}
      return false unless parsed.is_a?(Hash)

      al_folio = parsed["al_folio"]
      al_folio.is_a?(Hash) && al_folio[key].is_a?(Hash)
    rescue StandardError
      false
    end

    def using_core_theme?
      config_path = @root.join("_config.yml")
      return false unless config_path.file?

      begin
        parsed = parse_yaml(config_path.read) || {}
        parsed["theme"] == "al_folio_core" || Array(parsed["plugins"]).include?("al_folio_core")
      rescue StandardError
        false
      end
    end

    def parse_yaml(content)
      YAML.safe_load(content, permitted_classes: [Date, Time], aliases: true)
    end

    def manifest_paths
      if defined?(AlFolioCore) && AlFolioCore.respond_to?(:migration_manifest_paths)
        return Array(AlFolioCore.migration_manifest_paths).select { |path| File.file?(path) }
      end

      Dir.glob(@root.join("migrations/*.yml")).sort
    end

    def each_text_file
      FILE_GLOBS.each do |glob|
        Dir.glob(@root.join(glob)).sort.each do |path|
          next unless File.file?(path)
          next if ignored_path?(path)

          yield path
        end
      end
    end

    def ignored_path?(path)
      normalized = path.to_s
      IGNORE_PATH_PATTERNS.any? { |pattern| normalized.match?(pattern) }
    end

    def write_report(findings)
      by_severity = findings.group_by(&:severity)
      blocking = by_severity.fetch(:blocking, [])
      warning = by_severity.fetch(:warning, [])

      File.write(@root.join(REPORT_PATH), <<~MD)
        # al-folio upgrade report

        Generated by `bundle exec al-folio upgrade report`.

        ## Summary

        - Blocking findings: #{blocking.count}
        - Non-blocking findings: #{warning.count}

        ## Blocking

        #{format_findings(blocking)}

        ## Non-blocking

        #{format_findings(warning)}
      MD
    end

    def format_findings(findings)
      return "- None\n" if findings.empty?

      findings.map do |finding|
        "- [#{finding.id}] #{finding.message} (`#{finding.file}:#{finding.line}`)\n  - Snippet: `#{finding.snippet}`"
      end.join("\n") + "\n"
    end

    def print_summary(findings)
      blocking = findings.count { |finding| finding.severity == :blocking }
      warning = findings.count { |finding| finding.severity == :warning }
      @stdout.puts("Upgrade audit complete. Blocking: #{blocking}, Non-blocking: #{warning}.")
      @stdout.puts("Report: #{REPORT_PATH}")
    end
  end
end
