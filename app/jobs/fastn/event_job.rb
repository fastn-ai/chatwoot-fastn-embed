class Fastn::EventJob < ApplicationJob
  queue_as :medium
  retry_on Fastn::Client::Error, wait: :polynomially_longer, attempts: 5

  def perform(account_id, payload)
    account = Account.find_by(id: account_id)
    return if account.blank?

    Fastn::Client.new.deliver_event(account, payload)
  end
end
