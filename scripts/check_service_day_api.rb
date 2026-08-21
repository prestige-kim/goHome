#!/usr/bin/env ruby

require "json"
require "net/http"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SECRETS_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
WEEKDAY_DATE = "2026-08-21"
HOLIDAY_DATE = "2026-08-15"

def abort_with(message)
  warn "오류: #{message}"
  exit 1
end

def read_setting(contents, name)
  match = contents.match(/^\s*#{Regexp.escape(name)}\s*=\s*(.*?)\s*$/)
  match&.captures&.first.to_s.strip
end

def normalize_xcconfig_url(value)
  value.sub(%r{\Ahttps:/\$\(\)/}, "https://")
end

def get_json(uri, authorization: nil)
  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/json"
  request["Authorization"] = authorization if authorization

  response = Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: true,
    open_timeout: 10,
    read_timeout: 20
  ) { |http| http.request(request) }

  [response.code.to_i, JSON.parse(response.body)]
rescue JSON::ParserError
  abort_with("Worker가 JSON이 아닌 응답을 반환했습니다.")
rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
  abort_with("Worker 연결 실패 (#{error.class})")
end

def service_day_uri(base_url, date)
  uri = URI.join(base_url.delete_suffix("/") + "/", "v1/service-day")
  uri.query = URI.encode_www_form(date: date)
  uri
end

abort_with("Config/Secrets.xcconfig 파일이 없습니다.") unless File.file?(SECRETS_PATH)

contents = File.read(SECRETS_PATH)
base_url = normalize_xcconfig_url(read_setting(contents, "TRANSIT_PROXY_BASE_URL"))
client_token = read_setting(contents, "TRANSIT_PROXY_CLIENT_TOKEN")
abort_with("TRANSIT_PROXY_BASE_URL이 비어 있습니다.") if base_url.empty?
abort_with("TRANSIT_PROXY_CLIENT_TOKEN이 비어 있습니다.") if client_token.empty?
abort_with("Worker 주소는 HTTPS여야 합니다.") unless URI(base_url).scheme == "https"

health_uri = URI.join(base_url.delete_suffix("/") + "/", "health")
health_status, health_payload = get_json(health_uri)
abort_with("상태 확인 실패 (HTTP #{health_status})") unless
  health_status == 200 && health_payload["status"] == "ok"

unauthorized_status, unauthorized_payload = get_json(service_day_uri(base_url, HOLIDAY_DATE))
abort_with("공휴일 경로의 Bearer 인증 차단 확인 실패") unless
  unauthorized_status == 401 && unauthorized_payload["error"] == "unauthorized"

authorization = "Bearer #{client_token}"
weekday_status, weekday_payload = get_json(
  service_day_uri(base_url, WEEKDAY_DATE),
  authorization: authorization
)
abort_with("평일 판정 실패 (HTTP #{weekday_status})") unless
  weekday_status == 200 &&
  weekday_payload["date"] == WEEKDAY_DATE &&
  weekday_payload["type"] == "weekday" &&
  weekday_payload["holidayName"].nil?

holiday_status, holiday_payload = get_json(
  service_day_uri(base_url, HOLIDAY_DATE),
  authorization: authorization
)
abort_with("법정공휴일 판정 실패 (HTTP #{holiday_status})") unless
  holiday_status == 200 &&
  holiday_payload["date"] == HOLIDAY_DATE &&
  holiday_payload["type"] == "sunday_holiday" &&
  holiday_payload["holidayName"].to_s.include?("광복절")

puts "공휴일 Worker 종단간 점검"
puts "- HTTPS 상태: 정상"
puts "- 무인증 차단: 정상 (HTTP 401)"
puts "- #{WEEKDAY_DATE}: weekday"
puts "- #{HOLIDAY_DATE}: sunday_holiday / 광복절"
puts "- 비밀값·원본 응답: 출력하지 않음"
