#!/usr/bin/env ruby

require "open3"

ROOT = File.expand_path("..", __dir__)
PROTECTED_PATHS = [
  "Config/Secrets.xcconfig",
  "worker/.env.production",
  "worker/.dev.vars",
].freeze
FORBIDDEN_INFO_KEYS = %w[SeoulAPIKey PublicDataAPIKey].freeze
SECRET_ASSIGNMENT = /\b(?:SEOUL_API_KEY|PUBLIC_DATA_API_KEY|GOHOME_CLIENT_TOKEN|TRANSIT_PROXY_CLIENT_TOKEN)\b\s*(?::|=)\s*["']?([A-Za-z0-9_+\/=]{20,})/

if ARGV == ["--self-test"]
  secret_like = "SEOUL_API_KEY = #{"a" * 30}"
  placeholder = "SEOUL_API_KEY = your-seoul-api-key"
  unless secret_like.match?(SECRET_ASSIGNMENT) && !placeholder.match?(SECRET_ASSIGNMENT)
    abort("secret hygiene self-test: FAIL")
  end

  puts "secret hygiene self-test: PASS"
  exit 0
end

def git(*arguments)
  stdout, stderr, status = Open3.capture3("git", "-C", ROOT, *arguments)
  abort("secret hygiene: Git 검사 실패") unless status.success?
  [stdout, stderr]
end

failures = []

PROTECTED_PATHS.each do |path|
  _stdout, _stderr, ignored = Open3.capture3(
    "git", "-C", ROOT, "check-ignore", "--quiet", "--", path
  )
  failures << "보호 파일 ignore 누락: #{path}" unless ignored.success?

  tracked, = git("ls-files", "--", path)
  failures << "보호 파일이 Git에 추적됨: #{path}" unless tracked.empty?
end

tracked, = git("ls-files", "-z")
untracked, = git("ls-files", "--others", "--exclude-standard", "-z")
candidate_paths = (tracked + untracked).split("\0").reject(&:empty?).uniq

candidate_paths.each do |relative_path|
  path = File.join(ROOT, relative_path)
  next unless File.file?(path)
  next if File.size(path) > 2_000_000

  contents = File.binread(path)
  next if contents.include?("\0")

  contents.force_encoding(Encoding::UTF_8)
  next unless contents.valid_encoding?

  contents.each_line.with_index(1) do |line, line_number|
    next unless line.match?(SECRET_ASSIGNMENT)

    failures << "고엔트로피 비밀값 의심: #{relative_path}:#{line_number} (값 비공개)"
  end
end

info_plist_path = File.join(ROOT, "GoHome", "Resources", "Info.plist")
if File.file?(info_plist_path)
  info_plist = File.read(info_plist_path)
  FORBIDDEN_INFO_KEYS.each do |key|
    failures << "앱 Info.plist 금지 키 발견: #{key}" if info_plist.include?("<key>#{key}</key>")
  end
end

if failures.empty?
  puts "secret hygiene: PASS (비밀값은 읽거나 출력하지 않음)"
  exit 0
end

warn "secret hygiene: FAIL"
failures.each { |failure| warn "- #{failure}" }
exit 1
