#!/usr/bin/env ruby

require "securerandom"

PROJECT_ROOT = File.expand_path("..", __dir__)
XCCONFIG_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
WORKER_SECRETS_PATH = File.join(PROJECT_ROOT, "worker", ".env.production")

def abort_with(message)
  warn "오류: #{message}"
  exit 1
end

def read_setting(contents, name)
  match = contents.match(/^\s*#{Regexp.escape(name)}\s*=\s*(.*?)\s*$/)
  match&.captures&.first
end

def upsert_setting(contents, name, value)
  pattern = /^\s*#{Regexp.escape(name)}\s*=.*$/
  replacement = "#{name} = #{value}"

  if contents.match?(pattern)
    contents.sub(pattern, replacement)
  else
    "#{contents.rstrip}\n#{replacement}\n"
  end
end

abort_with("Config/Secrets.xcconfig 파일이 없습니다.") unless File.file?(XCCONFIG_PATH)

xcconfig = File.read(XCCONFIG_PATH)
seoul_api_key = read_setting(xcconfig, "SEOUL_API_KEY").to_s.strip
abort_with("SEOUL_API_KEY가 비어 있습니다.") if seoul_api_key.empty?

existing_worker_secrets = if File.file?(WORKER_SECRETS_PATH)
                            File.read(WORKER_SECRETS_PATH)
                          else
                            ""
                          end
public_data_api_key = read_setting(existing_worker_secrets, "PUBLIC_DATA_API_KEY").to_s.strip

client_token = read_setting(xcconfig, "TRANSIT_PROXY_CLIENT_TOKEN").to_s.strip
client_token = SecureRandom.hex(32) if client_token.empty?

updated_xcconfig = upsert_setting(xcconfig, "TRANSIT_PROXY_CLIENT_TOKEN", client_token)
proxy_base_url = ARGV.first.to_s.strip
unless proxy_base_url.empty?
  unless proxy_base_url.start_with?("https://")
    abort_with("Worker 주소는 https://로 시작해야 합니다.")
  end
  updated_xcconfig = upsert_setting(
    updated_xcconfig,
    "TRANSIT_PROXY_BASE_URL",
    proxy_base_url.delete_suffix("/")
  )
end
File.write(XCCONFIG_PATH, updated_xcconfig)

worker_secrets = <<~ENV_FILE
  SEOUL_API_KEY=#{seoul_api_key}
  GOHOME_CLIENT_TOKEN=#{client_token}
ENV_FILE
unless public_data_api_key.empty?
  worker_secrets << "PUBLIC_DATA_API_KEY=#{public_data_api_key}\n"
end
File.write(WORKER_SECRETS_PATH, worker_secrets)
File.chmod(0o600, WORKER_SECRETS_PATH)

puts "Worker 배포용 Secret 준비 완료"
puts "- 서울시 키: 설정됨 (값 비공개)"
puts "- 개인용 토큰: 설정됨 (값 비공개)"
puts "- 공공데이터 키: #{public_data_api_key.empty? ? '미설정' : '설정됨'} (값 비공개)"
puts "- Worker 주소: 설정됨" unless proxy_base_url.empty?
puts "- 배포 파일 권한: 0600"
