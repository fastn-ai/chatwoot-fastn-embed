// New or updated Chatwoot contact -> the customer's own CRM (HubSpot or Salesforce).
// A contact is created only when the CRM has none with that email. An existing CRM contact is
// never changed: the email is typed by a website visitor and nobody verified it, so it must not
// become a key for overwriting someone's record. Contacts with no email yet are left out.
const EVENTS = ["contact_created", "contact_updated"];
const PROVIDERS = ["hubspot", "salesforce"];
const NONE = { created: 0, unchanged: 0, skipped: 0, errors: 0 };
const SEARCH_PAGE_SIZE = 10;

function normalEmail(value) {
  return String(value ?? "").trim().toLowerCase();
}

function toCrmContact(e, provider) {
  const words = String(e.name ?? "").trim().split(/\s+/).filter(Boolean);
  const body = { email: normalEmail(e.email) };
  if (words.length > 1) {
    body.first_name = words[0];
    body.last_name = words.slice(1).join(" ");
  } else if (provider === "salesforce") {
    // Salesforce refuses a contact without a last name.
    body.last_name = words[0] ?? body.email.split("@")[0];
  } else if (words.length === 1) {
    body.first_name = words[0];
  }
  if (e.phone_number) body.phone = String(e.phone_number);
  return body;
}

async function sync(e, provider) {
  const email = normalEmail(e.email);
  const found = await fastn.unified.crm.contact.search({ email }, { provider, pageSize: SEARCH_PAGE_SIZE });
  const existing = (found?.records ?? []).find((record) => normalEmail(record?.data?.email) === email);
  if (existing) return { provider, action: "unchanged", id: existing.id };

  const created = await fastn.unified.crm.contact.create(toCrmContact(e, provider), { provider });
  return { provider, action: "created", id: created?.id ?? null };
}

export default async function (ctx) {
  const e = ctx.input ?? {};
  if (!EVENTS.includes(e.event)) {
    return { ...NONE, skipped: 1, reason: `event "${e.event ?? "none"}" is not a contact event` };
  }
  if (!normalEmail(e.email)) {
    return { ...NONE, skipped: 1, reason: "the contact has no email yet" };
  }

  const results = [];
  const errorDetails = [];
  for (const provider of PROVIDERS) {
    try {
      results.push(await sync(e, provider));
    } catch (err) {
      const message = String(err?.message ?? err);
      // The customer connects HubSpot, Salesforce or both: a CRM they did not connect is not an error.
      if (!message.includes("UNIFIED_NO_CONNECTED_PROVIDER")) errorDetails.push({ provider, errorMessage: message });
    }
  }
  if (results.length === 0 && errorDetails.length === 0) {
    return { ...NONE, skipped: 1, reason: "no CRM is connected for this customer" };
  }
  return {
    created: results.filter((r) => r.action === "created").length,
    unchanged: results.filter((r) => r.action === "unchanged").length,
    skipped: 0,
    errors: errorDetails.length,
    results,
    errorDetails,
  };
}
