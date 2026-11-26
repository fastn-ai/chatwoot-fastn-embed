class Api::V1::Accounts::Integrations::FastnController < Api::V1::Accounts::Integrations::BaseController
  before_action :check_admin_authorization?

  def embed_session
    return render json: { error: 'fastn_not_configured' }, status: :unprocessable_entity unless Fastn::Client.configured?

    render json: Fastn::Client.new.embed_session(Current.account)
  rescue Fastn::Client::Error => e
    Rails.logger.warn("[fastn] embed session failed: #{e.message}")
    render json: { error: 'fastn_unavailable' }, status: :bad_gateway
  end
end
