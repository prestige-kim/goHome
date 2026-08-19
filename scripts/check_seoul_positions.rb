#!/usr/bin/env ruby

require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SECRETS_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
SAMPLE_DIRECTORY = File.join(PROJECT_ROOT, "tmp", "api-samples")
DEFAULT_LINE = "2호선"
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

line_name = ARGV.first.to_s.strip
line_name = DEFAULT_LINE if line_name.empty?
api_key = read_api_key

uri = URI(
  "http://swopenapi.seoul.go.kr/api/subway/" \
  "#{path_segment(api_key)}/json/realtimePosition/0/100/" \
  "#{path_segment(line_name)}"
)

response = begin
  Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: 20) do |http|
    http.request(Net::HTTP::Get.new(uri))
  end
rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
  abort_with("서울시 API 연결 실패 (#{error.class})")
end

abort_with("HTTP #{response.code} 응답을 받았습니다.") unless response.is_a?(Net::HTTPSuccess)

payload = JSON.parse(response.body)
api_status = payload["errorMessage"] || payload["RESULT"] || {}
status_code = api_status["code"] || api_status["CODE"] || "확인 불가"
status_message = api_status["message"] || api_status["MESSAGE"] || "확인 불가"
positions = payload.fetch("realtimePositionList", [])

FileUtils.mkdir_p(SAMPLE_DIRECTORY)
safe_line_name = line_name.gsub(/[^0-9A-Za-z가-힣_-]/, "_")
sample_path = File.join(SAMPLE_DIRECTORY, "realtime-position-#{safe_line_name}.json")
File.write(sample_path, JSON.pretty_generate(payload))

expected_fields = %w[
  subwayId subwayNm statnId statnNm trainNo lastRecptnDt recptnDt
  updnLine statnTid statnTnm trainSttus directAt lstcarAt
]
response_fields = positions.flat_map(&:keys).uniq.sort
missing_fields = expected_fields - response_fields
status_counts = positions.each_with_object(Hash.new(0)) do |position, counts|
  counts[position["trainSttus"] || "없음"] += 1
end

puts "서울시 실시간 열차 위치 API 점검"
puts "- 조회 노선: #{line_name}"
puts "- HTTP 상태: #{response.code}"
puts "- API 상태: #{status_code} / #{status_message}"
puts "- 열차 위치 건수: #{positions.length}"
puts "- DTO 필드: #{missing_fields.empty? ? '모두 확인됨' : "미확인 #{missing_fields.join(', ')}"}"
puts "- 상태 코드별 건수: #{status_counts.sort.to_h}"
puts "- 응답 저장: #{sample_path.delete_prefix(PROJECT_ROOT + File::SEPARATOR)}"

positions.first(5).each_with_index do |position, index|
  puts(
    "  #{index + 1}. #{position['statnNm']} / #{position['updnLine']} / " \
    "상태 #{position['trainSttus']} / 종착 #{position['statnTnm']} / " \
    "급행 #{position['directAt']} / 막차 #{position['lstcarAt']}"
  )
end

exit(status_code == "INFO-000" && !positions.empty? ? 0 : 2)
