# Talks to fastn's partner API for this Chatwoot installation.
#
# Each Chatwoot account is one fastn customer, registered under the id "chatwoot-account-<id>".
# Integrations belong to the account, not to one agent, so every administrator of an account
# opens the hub as the same fastn user and sees the same connections.
#
# Calls are signed with fastn's identity headers (x-org-id / x-user-id / x-identity-hmac), so a
# call can only act for the customer it names. Nothing here knows which apps a customer has
# connected: Chatwoot only sends events, and that customer's integrations in fastn decide
# where they go.
class Fastn::Client
  class Error < StandardError; end

  TIMEOUT_SECONDS = 15
  HUB_USER_ID = 'chatwoot-admins'.freeze
  UNKNOWN_CUSTOMER = 'IDENTITY_ORG_NOT_FOUND'.freeze

  def self.configured?
    ENV.fetch('FASTN_API_KEY', '').present?
  end

  def self.event_urls
    ENV.fetch('FASTN_EVENT_URLS', '').split(',').map(&:strip).compact_blank
  end

  def self.customer_id(account)
    "chatwoot-account-#{account.id}"
  end

  def initialize(api_url: ENV.fetch('FASTN_API_URL', 'https://api.fastn.dev'),
                 api_key: ENV.fetch('FASTN_API_KEY', nil),
                 idv_secret: ENV.fetch('FASTN_IDV_SECRET', nil))
    @api_url = api_url.chomp('/')
    @api_key = api_key
    @idv_secret = idv_secret
  end

  # A short-lived address of the fastn hub for this account. The account becomes a fastn
  # customer the first time one of its administrators opens the hub.
  def embed_session(account)
    response = mint_token(account)
    if unknown_customer?(response)
      register_customer(account)
      response = mint_token(account)
    end
    raise Error, "embed token failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body).fetch('data')
    { iframe_url: "#{@api_url}/v1/embed/iframe?token=#{CGI.escape(data.fetch('token'))}", expires_at: data['expiresAt'] }
  end

  # Sends one Chatwoot event to every fastn event URL, as this account. An account that never
  # opened the hub is not a fastn customer and has no integrations, so its events are dropped.
  def deliver_event(account, payload)
    self.class.event_urls.each do |url|
      response = request(url, body: payload, org_id: self.class.customer_id(account), user_id: '')
      next if unknown_customer?(response)
      raise Error, "event delivery failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    end
  end

  private

  def mint_token(account)
    request("#{@api_url}/api/v1/embed/token", body: {}, org_id: self.class.customer_id(account), user_id: HUB_USER_ID)
  end

  def register_customer(account)
    response = request("#{@api_url}/api/v1/orgs", body: { name: account.name, orgId: self.class.customer_id(account) },
                                                  org_id: '', user_id: HUB_USER_ID)
    return if response.is_a?(Net::HTTPSuccess) || response.code == '409'

    hint = response.code == '403' ? ' (the fastn API key needs Full Access to register customers)' : ''
    raise Error, "register customer failed: #{response.code}#{hint}"
  end

  def unknown_customer?(response)
    response.code == '404' && response.body.to_s.include?(UNKNOWN_CUSTOMER)
  end

  def request(url, body:, org_id:, user_id:)
    uri = URI.parse(url)
    req = Net::HTTP::Post.new(uri)
    headers(org_id, user_id).each { |name, value| req[name] = value }
    req.body = body.to_json
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) { |http| http.request(req) }
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise Error, "fastn unreachable: #{e.class}"
  end

  def headers(org_id, user_id)
    headers = { 'Content-Type' => 'application/json', 'x-api-key' => @api_key }
    headers['X-fastn-Test-Mode'] = 'true' if @api_key.to_s.start_with?('fsk_test_')
    headers['x-org-id'] = org_id if org_id.present?
    headers['x-user-id'] = user_id if user_id.present?
    headers['x-identity-hmac'] = OpenSSL::HMAC.hexdigest('SHA256', @idv_secret, "#{org_id}\n#{user_id}") if @idv_secret.present?
    headers
  end
end
