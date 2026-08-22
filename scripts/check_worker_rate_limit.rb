#!/usr/bin/env ruby

require "json"
require "net/http"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SECRETS_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
REQUEST_COUNT = 13

def abort_with(message)
  warn "오류: #{message}"
  exit 1
end

def read_setting(contents, name)
  match = contents.match(/^\s*#{Regexp.escape(name)}\s*=\s*(.*?)\s*$/)
  match&.captures&.first.to_s.strip
end

abort_with("Config/Secrets.xcconfig 파일이 없습니다.") unless File.file?(SECRETS_PATH)

contents = File.read(SECRETS_PATH)
base_url = read_setting(contents, "TRANSIT_PROXY_BASE_URL")
  .sub(%r{\Ahttps:/\$\(\)/}, "https://")
client_token = read_setting(contents, "TRANSIT_PROXY_CLIENT_TOKEN")
abort_with("Worker 설정이 비어 있습니다.") if base_url.empty? || client_token.empty?

uri = URI.join(base_url.delete_suffix("/") + "/", "v1/arrivals")
uri.query = URI.encode_www_form(station: "시청")
abort_with("Worker 주소는 HTTPS여야 합니다.") unless uri.scheme == "https"

statuses = Hash.new(0)
limited_payload = nil
Net::HTTP.start(
  uri.host,
  uri.port,
  use_ssl: true,
  open_timeout: 10,
  read_timeout: 20
) do |http|
  REQUEST_COUNT.times do
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{client_token}"
    response = http.request(request)
    statuses[response.code.to_i] += 1
    limited_payload = JSON.parse(response.body) if response.code.to_i == 429
  end
end

unless statuses[200] == 12 && statuses[429] == 1 && limited_payload == { "error" => "rate_limited" }
  abort_with("실시간 경로 속도 제한 결과가 예상과 다릅니다. 상태별 건수: #{statuses.sort.to_h}")
end

puts "Worker 실시간 경로 속도 제한 점검"
puts "- 허용: HTTP 200 12건"
puts "- 차단: HTTP 429 1건"
puts "- 비밀값·응답 전문: 출력하지 않음"
puts "- 참고: 동일 요청은 20초 캐시되어 원본 호출을 합칩니다."
