#!/usr/bin/env ruby

require "json"
require "fileutils"
require "net/http"
require "uri"

PROJECT_ROOT = File.expand_path("..", __dir__)
SECRETS_PATH = File.join(PROJECT_ROOT, "Config", "Secrets.xcconfig")
DEFAULT_STATION = "시청"
DEFAULT_LINE = "2호선"
SAMPLE_DIRECTORY = File.join(PROJECT_ROOT, "tmp", "api-samples")

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

  [response, JSON.parse(response.body)]
rescue JSON::ParserError
  abort_with("Worker가 JSON이 아닌 응답을 반환했습니다.")
rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
  abort_with("Worker 연결 실패 (#{error.class})")
end

abort_with("Config/Secrets.xcconfig 파일이 없습니다.") unless File.file?(SECRETS_PATH)

contents = File.read(SECRETS_PATH)
base_url = normalize_xcconfig_url(read_setting(contents, "TRANSIT_PROXY_BASE_URL"))
client_token = read_setting(contents, "TRANSIT_PROXY_CLIENT_TOKEN")
station = ARGV.first.to_s.strip
station = DEFAULT_STATION if station.empty?
line_name = ARGV[1].to_s.strip
line_name = DEFAULT_LINE if line_name.empty?

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

position_uri = URI.join(base_url.delete_suffix("/") + "/", "v1/positions")
position_uri.query = URI.encode_www_form(line: line_name)
unauthorized_position_response, unauthorized_position_payload = get_json(position_uri)
unless unauthorized_position_response.code.to_i == 401 &&
       unauthorized_position_payload["error"] == "unauthorized"
  abort_with("열차 위치 경로의 Bearer 인증 차단 확인 실패")
end
position_response, position_payload = get_json(
  position_uri,
  authorization: "Bearer #{client_token}"
)
unless position_response.is_a?(Net::HTTPSuccess)
  abort_with("열차 위치 중계 실패 (HTTP #{position_response.code})")
end

position_api_status = position_payload["errorMessage"] || position_payload["RESULT"] || {}
position_status_code = position_api_status["code"] || position_api_status["CODE"] || "확인 불가"
position_status_message = position_api_status["message"] || position_api_status["MESSAGE"] || "확인 불가"
positions = position_payload.fetch("realtimePositionList", [])
position_fields = positions.flat_map(&:keys).uniq.sort
expected_position_fields = %w[
  subwayId subwayNm statnId statnNm trainNo lastRecptnDt recptnDt
  updnLine statnTid statnTnm trainSttus directAt lstcarAt
]
missing_position_fields = expected_position_fields - position_fields
position_status_counts = positions.each_with_object(Hash.new(0)) do |position, counts|
  counts[position["trainSttus"] || "없음"] += 1
end

seoul_now = Time.now.getlocal("+09:00")
service_date = seoul_now.strftime("%Y-%m-%d")
calendar_service_day = case seoul_now.wday
                       when 0 then "sunday_holiday"
                       when 6 then "saturday"
                       else "weekday"
                       end
service_day_uri = URI.join(base_url.delete_suffix("/") + "/", "v1/service-day")
service_day_uri.query = URI.encode_www_form(date: service_date)
service_day_response, service_day_payload = get_json(
  service_day_uri,
  authorization: "Bearer #{client_token}"
)
allowed_service_days = %w[weekday saturday sunday_holiday]
if service_day_response.is_a?(Net::HTTPSuccess) &&
   allowed_service_days.include?(service_day_payload["type"])
  service_day = service_day_payload["type"]
  service_day_state = service_day
elsif service_day_response.code.to_i == 500 &&
      service_day_payload["error"] == "missing_public_data_api_key"
  service_day = calendar_service_day
  service_day_state = "공공데이터 키 미설정 (요일 폴백)"
else
  service_day = calendar_service_day
  service_day_state = "검증 실패 (HTTP #{service_day_response.code})"
end
directions = line_name == "2호선" ? %w[inner outer] : %w[up down]
last_train_uri = URI.join(base_url.delete_suffix("/") + "/", "v1/last-trains")
last_train_uri.query = URI.encode_www_form(
  station: station,
  line: line_name,
  direction: directions.first,
  serviceDay: service_day,
  date: service_date
)
unauthorized_last_train_response, unauthorized_last_train_payload = get_json(last_train_uri)
unless unauthorized_last_train_response.code.to_i == 401 &&
       unauthorized_last_train_payload["error"] == "unauthorized"
  abort_with("막차 시간표 경로의 Bearer 인증 차단 확인 실패")
end

last_train_results = directions.to_h do |direction|
  direction_uri = URI(last_train_uri.to_s)
  direction_uri.query = URI.encode_www_form(
    station: station,
    line: line_name,
    direction: direction,
    serviceDay: service_day,
    date: service_date
  )
  response, payload = get_json(
    direction_uri,
    authorization: "Bearer #{client_token}"
  )
  unless response.is_a?(Net::HTTPSuccess)
    abort_with("막차 시간표 중계 실패 (#{direction}, HTTP #{response.code})")
  end
  status_code = payload.dig("response", "header", "resultCode") || "확인 불가"
  items = payload.dig("response", "body", "items", "item")
  rows = items.is_a?(Array) ? items : Array(items).compact
  required_fields = %w[upbdnbSe lineNm stnNm trainDptreTm]
  invalid_field_rows = rows.count do |row|
    required_fields.any? { |field| row[field].to_s.strip.empty? }
  end
  invalid_time_rows = rows.count do |row|
    !row["trainDptreTm"].to_s.match?(/\A\d{2}:?\d{2}(?::?\d{2})?\z/)
  end
  [direction, {
    status_code: status_code,
    row_count: rows.length,
    invalid_field_rows: invalid_field_rows,
    invalid_time_rows: invalid_time_rows,
  }]
end

FileUtils.mkdir_p(SAMPLE_DIRECTORY)
safe_line_name = line_name.gsub(/[^0-9A-Za-z가-힣_-]/, "_")
position_sample_path = File.join(
  SAMPLE_DIRECTORY,
  "worker-realtime-position-#{safe_line_name}.json"
)
File.write(position_sample_path, JSON.pretty_generate(position_payload))

puts "Cloudflare Worker 종단간 점검"
puts "- HTTPS 상태: 정상"
puts "- 토큰 인증: 정상"
puts "- 조회역: #{station}"
puts "- 서울시 API 상태: #{status_code} / #{status_message}"
puts "- 도착정보 건수: #{arrivals.length}"
puts "- 위치 조회 노선: #{line_name}"
puts "- 위치 API 상태: #{position_status_code} / #{position_status_message}"
puts "- 열차 위치 건수: #{positions.length}"
puts "- 위치 DTO 필드: #{missing_position_fields.empty? ? '모두 확인됨' : "미확인 #{missing_position_fields.join(', ')}"}"
puts "- 위치 상태 코드별 건수: #{position_status_counts.sort.to_h}"
puts "- 위치 응답 저장: #{position_sample_path.delete_prefix(PROJECT_ROOT + File::SEPARATOR)}"
puts "- 막차 시간표 인증: 정상"
last_train_results.each do |direction, result|
  puts "- 막차 시간표 #{direction}: 원본 코드 #{result[:status_code]}, #{result[:row_count]}행"
  puts "  필수 필드 누락 #{result[:invalid_field_rows]}행, 시간 형식 오류 #{result[:invalid_time_rows]}행"
end
puts "- 공휴일 판정: #{service_day_state}"

success = %w[INFO-000 00].include?(status_code) && !arrivals.empty? &&
  position_status_code == "INFO-000" && !positions.empty? &&
  last_train_results.values.all? { |result|
    result[:status_code] == "00" && result[:row_count].positive? &&
      result[:invalid_field_rows].zero? && result[:invalid_time_rows].zero?
  } &&
  !service_day_state.start_with?("검증 실패")
exit(success ? 0 : 2)
