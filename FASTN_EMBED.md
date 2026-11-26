# Chatwoot with fastn embedded

This fork adds an **Integrations by fastn** card to Chatwoot's Settings → Integrations page.
Each Chatwoot account connects its own apps there, and Chatwoot sends its events to
[fastn](https://fastn.ai), which runs that account's integrations.

Two integrations are set up:

| Integration | What it does | Apps |
|---|---|---|
| Team chat notifications | Posts each new conversation to a channel the account picks | Slack or Microsoft Teams |
| CRM contact sync | Adds each contact that is not in the CRM yet, matched by email | HubSpot or Salesforce |

Upstream: [chatwoot/chatwoot](https://github.com/chatwoot/chatwoot), release 4.20.1.

## How it works

```
Chatwoot                                  fastn                               The account's apps
--------                                  -----                               ------------------
conversation_created  ─┐
contact_created       ─┼─ one event URL ─▶ finds the account's integration ─▶ Slack or Teams
contact_updated       ─┘  signed per       and runs its flow                  HubSpot or Salesforce
                          account
```

- **Chatwoot only sends events.** It does not know which apps an account connected. Adding
  another app to an integration is done in fastn, with no change here.
- **Each Chatwoot account is one fastn customer**, registered as `chatwoot-account-<id>` the
  first time one of its administrators opens the hub.
- **The hub is fastn's page in an iframe.** Chatwoot's backend asks fastn for a short-lived
  address of it, so the fastn API key never reaches the browser.
- **Every call is signed** with the account's id (`x-org-id` and `x-identity-hmac`), so a call
  can only act for the account it names.

## What changed in Chatwoot

| File | Purpose |
|---|---|
| `app/services/fastn/client.rb` | Signs and sends the three fastn calls: hub session, register account, deliver event |
| `app/controllers/api/v1/accounts/integrations/fastn_controller.rb` | `POST .../integrations/fastn/embed_session`, administrators only |
| `app/listeners/fastn_listener.rb` | Picks up `conversation_created`, `contact_created` and `contact_updated` |
| `app/jobs/fastn/event_job.rb` | Delivers an event in the background, with retries |
| `app/dispatchers/async_dispatcher.rb` | Registers the listener |
| `app/models/integrations/app.rb`, `config/integration/apps.yml`, `config/locales/en.yml` | The card on the Integrations page |
| `app/javascript/dashboard/routes/dashboard/settings/integrations/Fastn.vue` and `integrations.routes.js` | The page that shows the hub |
| `app/javascript/dashboard/api/integrations/fastn.js` | Front-end call for the hub session |
| `fastn/workflows/*.js` | The two fastn flows, kept here for reference |

## Set up fastn (once)

Do this in your own fastn workspace. The quickest way is to ask Claude with the fastn MCP
connected to do it from this file.

1. **Integrations.** Create two widgets, each attached to one unified entity:
   - "Team chat notifications": Messaging → Channel Message, providers Slack and Microsoft Teams.
     Give it a channel picker per provider (Slack `channel`; Teams `teamId` and `channelId`).
   - "CRM contact sync": CRM → Contact, providers HubSpot and Salesforce.

   Mark both providers of each widget optional, so connecting one app is enough.
2. **Flows.** Create and publish one workflow from each file in `fastn/workflows/`, and attach
   each to its widget.
3. **Event URL.** Create one webhook trigger (auth: API key) with a route to each workflow.
   Give each route a tenant resolver on the header `x-end-org-id`, so every event runs for the
   account that sent it.
4. **API key.** Create a key with identity verification on. It needs Full Access to register
   accounts as customers.

## Run it

Add these to Chatwoot's `.env`:

```
FASTN_API_URL=https://api.fastn.dev
FASTN_API_KEY=<your fastn API key>
FASTN_IDV_SECRET=<the key's identity verification secret>
FASTN_EVENT_URLS=<the webhook trigger URL from step 3>
```

Then start Chatwoot as usual, open Settings → Integrations → Integrations by fastn, and connect
an app. Without `FASTN_API_KEY` the card is hidden and nothing is sent.

## Limits

- A contact with no email is not sent to the CRM; it is sent once the visitor gives one.
- A contact that is already in the CRM is never changed. The email is typed by a website visitor and
  not verified, so it must not become a way to overwrite someone's CRM record.
- Visitor text (name, email, message) is escaped before it is posted to Slack or Teams, so a
  visitor cannot ping a channel or hide a link.
- Events of an account that never opened the hub are dropped: it has no integrations.
- Only English strings were added.
