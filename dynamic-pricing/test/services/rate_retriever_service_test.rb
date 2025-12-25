require "test_helper"
require "minitest/mock"
require "net/http"



class RateRetrieverServiceTest < ActiveSupport::TestCase
  test "call sends request with correct payload" do
    payload_check = ->(request) do
      body = JSON.parse(request.body)
      attributes = body["attributes"]
      # 4 periods * 3 hotels * 3 rooms = 36 combinations
      assert_equal 36, attributes.size
      assert_equal "04aa6f42aa03f220c2ae9a276cd68c62", request["token"]
      true
    end

    response_mock = Minitest::Mock.new
    response_mock.expect :code, "200"
    response_mock.expect :body, "{\"rates\": []}"

    Net::HTTP.stub :new, ->(host, port) {
      http_mock = Minitest::Mock.new
      http_mock.expect :request, response_mock do |req|
        payload_check.call(req)
      end
      http_mock
    } do
      RateRetrieverService.call
    end
  end
end
