# frozen_string_literal: true

require "optparse"
require "pathname"

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
      check_config_contract(findings)
      check_legacy_assets(findings)
      check_legacy_patterns(findings)
      findings
    end

    def check_config_contract(findings)
      config_path = @root.join("_config.yml")
      return unless config_path.file?

      content = config_path.read
      unless content.match?(/^al_folio:\s*$/)
        findings << Finding.new(
          id: "missing_al_folio_namespace",
          severity: :blocking,
          message: "Missing `al_folio` config namespace required for v1.x.",
          file: "_config.yml",
          line: 1,
          snippet: "Add al_folio.api_version, style_engine, compat, and upgrade keys."
        )
      end

      unless content.match?(/^\s*style_engine:\s*tailwind\s*$/)
        findings << Finding.new(
          id: "style_engine_not_tailwind",
          severity: :blocking,
          message: "`al_folio.style_engine` should be set to `tailwind` for v1.x.",
          file: "_config.yml",
          line: 1,
          snippet: "Set al_folio.style_engine: tailwind"
        )
      end
    end

    def check_legacy_assets(findings)
      files = ["_includes/head.liquid", "_includes/scripts.liquid", "_includes/distill_scripts.liquid"]
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
      return content if content.match?(/^al_folio:\s*$/)

      block = <<~YAML

        al_folio:
          api_version: 1
          style_engine: tailwind
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
