# Task Format — Agent Output Specification

The agent must output **only** a JSON array of task objects. No prose, no
explanation, no markdown — just the array. An empty array `[]` is valid if
no actionable items are found.

---

## Field definitions

| Field         | Type     | Required | Description                                                                 |
|---------------|----------|----------|-----------------------------------------------------------------------------|
| `title`       | string   | yes      | Short task title. Max 80 characters.                                        |
| `description` | string   | yes      | Full context: what needs doing, relevant quotes, links. May be multi-line.  |
| `label`       | string   | yes      | Exactly one of: `Do myself`, `AI-assisted`, `Auto-execute`, `Today`         |
| `priority`    | integer  | yes      | 0 = no priority, 1 = urgent, 2 = high, 3 = medium, 4 = low                 |
| `source_id`   | string   | yes      | Message ID from Gmail or Slack (used for deduplication).                    |
| `source_url`  | string   | no       | Deep link to the original message, if available.                            |

---

## JSON Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["title", "description", "label", "priority", "source_id"],
    "additionalProperties": false,
    "properties": {
      "title": {
        "type": "string",
        "maxLength": 80
      },
      "description": {
        "type": "string"
      },
      "label": {
        "type": "string",
        "enum": ["Do myself", "AI-assisted", "Auto-execute", "Today"]
      },
      "priority": {
        "type": "integer",
        "minimum": 0,
        "maximum": 4
      },
      "source_id": {
        "type": "string"
      },
      "source_url": {
        "type": "string",
        "format": "uri"
      }
    }
  }
}
```

---

## Worked examples

### Example 1 — Do myself (personal decision required)

```json
[
  {
    "title": "Reply to Alice re: contract renewal",
    "description": "Alice emailed asking whether you want to renew the consulting contract for another 6 months. She needs an answer by Friday.\n\nOriginal message: 'Hi, just checking in on the contract renewal — please let me know by EOW.'",
    "label": "Do myself",
    "priority": 2,
    "source_id": "18e4c2a1f9d3b7e0",
    "source_url": "https://mail.google.com/mail/u/0/#inbox/18e4c2a1f9d3b7e0"
  }
]
```

### Example 2 — AI-assisted (user needs help, AI can assist)

```json
[
  {
    "title": "Draft response to RFP from Acme Corp",
    "description": "Acme Corp sent an RFP for a 3-month data pipeline project. The scope covers ETL, reporting, and a dashboard. Deadline for submission is 2026-03-20.\n\nKey requirements from the email: scalable ingestion, daily refresh, Tableau-compatible output.",
    "label": "AI-assisted",
    "priority": 1,
    "source_id": "18e4c2a1f9d3b7e1"
  }
]
```

### Example 3 — Auto-execute (fully delegatable)

```json
[
  {
    "title": "Add meeting notes from Tuesday standup to Notion",
    "description": "The standup notes were pasted into Slack #general at 09:15 UTC. Content: 'Shipped auth fix. Working on payment retries. Blocker: waiting on design review.'\n\nAction: create a new page in the Engineering > Standups Notion database with today's date and this content.",
    "label": "Auto-execute",
    "priority": 3,
    "source_id": "C04AB12XY-1710234900.123456"
  }
]
```

---

## Malformed message handling

If a message cannot be parsed or is clearly not actionable (spam, auto-reply,
newsletter), output an empty array:

```json
[]
```

Do not create a task to report the failure. Silently skip non-actionable messages.

---

## Rules (reminder)

- Output an **array only**. Never wrap in an object. Never add keys outside the schema.
- One task per distinct actionable item. Split compound emails into multiple tasks.
- `source_id` must be the exact Gmail message ID or Slack message timestamp — no truncation.
