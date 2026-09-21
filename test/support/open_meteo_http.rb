# A deterministic HTTP boundary: no test needs a network connection.
class OpenMeteoHTTP
  Response = Data.define(:code, :body)
  attr_reader :host, :port, :options, :requests
  attr_accessor :body, :code, :error

  def initialize
    @body = File.read(Rails.root.join("test/fixtures/files/open_meteo/hourly.json"))
    @code = "200"
    @requests = []
  end

  def start(host, port, **options)
    @host, @port, @options = host, port, options
    yield self
  end

  def request(request)
    @requests << request
    raise error if error
    Response.new(code: code, body: body)
  end

  def change_payload
    payload = JSON.parse(body)
    yield payload
    self.body = JSON.generate(payload)
  end
end
