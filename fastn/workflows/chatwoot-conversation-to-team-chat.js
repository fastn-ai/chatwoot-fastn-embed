// New Chatwoot conversation -> the customer's own Slack or Microsoft Teams channel.
// Chatwoot sends its conversation_created event; the channel is the one the customer picked in the
// "Team chat notifications" integration, which fastn merges into the call for that customer.
const EVENT = "conversation_created";
const CUSTOMER_CHANNEL = "set-by-customer";
const MAX_MESSAGE_CHARS = 500;
// The line break each app understands: Slack takes text, Teams takes HTML.
const LINE_BREAK = { slack: "\n", microsoftTeams: "<br>" };

// Names, emails and messages are typed by website visitors. Unescaped, "<!channel>" would ping a
// whole Slack channel and a tag would be rendered by Teams, so &, < and > are always escaped.
function plain(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function describe(e, lineBreak) {
  const sender = e?.meta?.sender ?? {};
  const name = sender.name ? plain(sender.name) : "";
  const email = sender.email ? plain(sender.email) : "";
  const contact = name && email ? `${name} (${email})` : name || email || "a visitor";
  const lines = [`New conversation #${plain(e.id)} from ${contact} in ${plain(e.account?.name ?? "Chatwoot")}`];
  if (e.channel) lines.push(`Channel: ${plain(String(e.channel).replace("Channel::", ""))}`);
  const message = (e.messages ?? [])[0]?.content;
  if (message) lines.push(`"${plain(String(message).slice(0, MAX_MESSAGE_CHARS))}"`);
  return lines.join(lineBreak);
}

export default async function (ctx) {
  const e = ctx.input ?? {};
  if (e.event !== EVENT) {
    return { posted: 0, skipped: 1, errors: 0, reason: `event "${e.event ?? "none"}" is not ${EVENT}` };
  }
  if (!e.id) {
    return { posted: 0, skipped: 0, errors: 1, errorDetails: [{ errorMessage: "conversation id is missing" }] };
  }

  const sent = [];
  const errorDetails = [];
  for (const provider of Object.keys(LINE_BREAK)) {
    const text = describe(e, LINE_BREAK[provider]);
    try {
      const posted = await fastn.unified.messaging.channel_message.create({ channel_id: CUSTOMER_CHANNEL, text }, { provider });
      sent.push({ provider, messageId: posted?.id ?? null, text });
    } catch (err) {
      const message = String(err?.message ?? err);
      // The customer connects Slack, Teams or both: an app they did not connect is not an error.
      if (!message.includes("UNIFIED_NO_CONNECTED_PROVIDER")) errorDetails.push({ provider, errorMessage: message });
    }
  }
  if (sent.length === 0 && errorDetails.length === 0) {
    return { posted: 0, skipped: 1, errors: 0, reason: "no chat app is connected for this customer" };
  }
  return { posted: sent.length, skipped: 0, errors: errorDetails.length, sent, errorDetails };
}
