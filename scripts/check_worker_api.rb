#!/usr/bin/env ruby

require "json"
require "net/http"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SECRETS_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
DEFAULT_STATION = "시청"

def abort_with(message)
  warn "오류: #{message}"
  exit 1
end

def read_setting(contents, name)
  match = contents.match(/^\s*#{Regexp.escape(name)}\s*=\s*(.*?)\s*$/)
  match&.captures&.first.to_s.strip
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

  [response, JSON.parse(response.body)]
rescue JSON::ParserError
  abort_with("Worker가 JSON이 아닌 응답을 반환했습니다.")
rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
  abort_with("Worker 연결 실패 (#{error.class})")
end

abort_with("Config/Secrets.xcconfig 파일이 없습니다.") unless File.file?(SECRETS_PATH)

contents = File.read(SECRETS_PATH)
base_url = read_setting(contents, "TRANSIT_PROXY_BASE_URL")
client_token = read_setting(contents, "TRANSIT_PROXY_CLIENT_TOKEN")
station = ARGV.first.to_s.strip
station = DEFAULT_STATION if station.empty?

abort_with("TRANSIT_PROXY_BASE_URL이 비어 있습니다.") if base_url.empty?
abort_with("TRANSIT_PROXY_CLIENT_TOKEN이 비어 있습니다.") if client_token.empty?

base_uri = URI(base_url)
abort_with("Worker 주소는 HTTPS여야 합니다.") unless base_uri.scheme == "https"

health_uri = URI.join(base_url.delete_suffix("/") + "/", "health")
health_response, health_payload = get_json(health_uri)
unless health_response.is_a?(Net::HTTPSuccess) && health_payload["status"] == "ok"
  abort_with("Worker 상태 확인 실패 (HTTP #{health_response.code})")
end

arrival_uri = URI.join(base_url.delete_suffix("/") + "/", "v1/arrivals")
arrival_uri.query = URI.encode_www_form(station: station)
arrival_response, arrival_payload = get_json(
  arrival_uri,
  authorization: "Bearer #{client_token}"
)
unless arrival_response.is_a?(Net::HTTPSuccess)
  abort_with("도착정보 중계 실패 (HTTP #{arrival_response.code})")
end

api_status = arrival_payload["errorMessage"] || arrival_payload["RESULT"] || {}
status_code = api_status["code"] || api_status["CODE"] || "확인 불가"
status_message = api_status["message"] || api_status["MESSAGE"] || "확인 불가"
arrivals = arrival_payload.fetch("realtimeArrivalList", [])

puts "Cloudflare Worker 종단간 점검"
puts "- HTTPS 상태: 정상"
puts "- 토큰 인증: 정상"
puts "- 조회역: #{station}"
puts "- 서울시 API 상태: #{status_code} / #{status_message}"
puts "- 도착정보 건수: #{arrivals.length}"

exit(status_code == "INFO-000" && !arrivals.empty? ? 0 : 2)
