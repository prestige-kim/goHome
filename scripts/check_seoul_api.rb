#!/usr/bin/env ruby

require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SECRETS_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
SAMPLE_DIRECTORY = File.join(PROJECT_ROOT, "tmp", "api-samples")
DEFAULT_STATION = "시청"
INSECURE_HTTP_FLAG = "--allow-insecure-http"

def abort_with(message)
  warn "오류: #{message}"
  exit 1
end

def read_api_key
  abort_with("Config/Secrets.xcconfig 파일이 없습니다.") unless File.file?(SECRETS_PATH)

  line = File.readlines(SECRETS_PATH, chomp: true).find do |candidate|
    candidate.match?(/^\s*SEOUL_API_KEY\s*=/)
  end
  abort_with("SEOUL_API_KEY 항목을 찾지 못했습니다.") unless line

  key = line.split("=", 2).last.to_s.strip
  if key.empty? || key.include?("YOUR_") || key.include?("여기에")
    abort_with("SEOUL_API_KEY가 비어 있거나 예시 값입니다.")
  end

  key
end

def path_segment(value)
  URI.encode_www_form_component(value).gsub("+", "%20")
end

allow_insecure_http = ARGV.delete(INSECURE_HTTP_FLAG)
unless allow_insecure_http
  abort_with(
    "서울시 지하철 API는 HTTP만 지원합니다. 키가 암호화되지 않은 채 전송됩니다. " \
    "위험을 이해하고 1회 점검하려면 #{INSECURE_HTTP_FLAG} 옵션을 명시하세요."
  )
end

station = ARGV.first.to_s.strip
station = DEFAULT_STATION if station.empty?
api_key = read_api_key

uri = URI(
  "http://swopenapi.seoul.go.kr/api/subway/" \
  "#{path_segment(api_key)}/json/realtimeStationArrival/0/20/" \
  "#{path_segment(station)}"
)

request = Net::HTTP::Get.new(uri)
response = begin
  Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: 10,
    read_timeout: 20
  ) { |http| http.request(request) }
rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
  abort_with("서울시 API 연결 실패 (#{error.class})")
end

abort_with("HTTP #{response.code} 응답을 받았습니다.") unless response.is_a?(Net::HTTPSuccess)

payload = JSON.parse(response.body)
api_status = payload["errorMessage"] || payload["RESULT"] || {}
status_code = api_status["code"] || api_status["CODE"] || "확인 불가"
status_message = api_status["message"] || api_status["MESSAGE"] || "확인 불가"
arrivals = payload.fetch("realtimeArrivalList", [])

FileUtils.mkdir_p(SAMPLE_DIRECTORY)
safe_station_name = station.gsub(/[^0-9A-Za-z가-힣_-]/, "_")
sample_path = File.join(SAMPLE_DIRECTORY, "realtime-arrival-#{safe_station_name}.json")
File.write(sample_path, JSON.pretty_generate(payload))

dto_fields = %w[
  subwayId updnLine trainLineNm statnNm barvlDt arvlMsg2
  btrainNo bstatnNm btrainSttus lstcarAt arvlCd recptnDt
]
response_fields = arrivals.flat_map(&:keys).uniq.sort
missing_fields = dto_fields - response_fields

puts "서울시 실시간 지하철 도착 API 점검"
puts "- 조회역: #{station}"
puts "- API 상태: #{status_code} / #{status_message}"
puts "- 도착정보 건수: #{arrivals.length}"
puts "- DTO 필드: #{missing_fields.empty? ? '모두 확인됨' : "미확인 #{missing_fields.join(', ')}"}"
puts "- 응답 필드 수: #{response_fields.length}"
puts "- 응답 저장: #{sample_path.delete_prefix(PROJECT_ROOT + File::SEPARATOR)}"

arrivals.first(3).each_with_index do |arrival, index|
  puts(
    "  #{index + 1}. #{arrival['statnNm']} / #{arrival['trainLineNm']} / " \
    "#{arrival['arvlMsg2']} (#{arrival['barvlDt']}초)"
  )
end

exit(status_code == "INFO-000" && !arrivals.empty? ? 0 : 2)
