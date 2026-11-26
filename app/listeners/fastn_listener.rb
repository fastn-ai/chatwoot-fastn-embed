# Sends Chatwoot events to fastn. Chatwoot does not know which apps a customer has connected:
# fastn routes each event to the integrations that account turned on (Slack, Teams, HubSpot...).
class FastnListener < BaseListener
  # A website visitor is created without an email and gives it later, so the CRM integration
  # needs the update as well as the create. Updates that change nothing a CRM stores are not sent.
  CONTACT_FIELDS = %w[name email phone_number].freeze

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    publish(conversation.account, conversation.webhook_data.merge(event: __method__.to_s))
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    publish(account, contact.webhook_data.merge(event: __method__.to_s))
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    changed = extract_changed_attributes(event)
    return if changed.blank?
    return unless changed.flat_map(&:keys).map(&:to_s).intersect?(CONTACT_FIELDS)

    publish(account, contact.webhook_data.merge(event: __method__.to_s, changed_attributes: changed))
  end

  private

  def publish(account, payload)
    return unless Fastn::Client.configured? && Fastn::Client.event_urls.any?

    Fastn::EventJob.perform_later(account.id, payload.as_json)
  end
end
