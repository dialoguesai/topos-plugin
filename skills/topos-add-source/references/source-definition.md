# Private source JSON

The CLI accepts the node's `DataSourceDefinition` fields and rejects unknown fields. There
is no `visibility`, publication, caller-selected owner or account field. Use unique lowercase
source ids (maximum 80 characters), and unique schema/parser ids for custom extract maps.
Never replace bundled definitions or reuse a custom parser id from another source.

## Human conversation export

For input records like:

```json
[{"id":"my_messages:one","thread":"example-thread","role":"user","text":"Synthetic example","date":"2026-01-01T12:00:00Z"}]
```

Use:

```json
{
  "source_id": "my_messages",
  "display_name": "My messages",
  "source_type": "file",
  "delivery": "owner_upload",
  "schema_id": "my.messages.v1",
  "parser_id": "my.messages.v1",
  "canonical_mapper_id": "my_messages",
  "canonical_group_id": "conversations",
  "default_scope_id": "messages",
  "allowed_scope_ids": ["messages:read"],
  "posture": "mixed",
  "enrichment_trigger": "automatic",
  "file_ingest_shape": {
    "format": "json",
    "parser_extract_map": {
      "message_id": "id",
      "conversation_id": "thread",
      "sender_type": "role",
      "content": "text",
      "event_at": "date"
    }
  }
}
```

Use this lane for human messages, not notes, transactions or arbitrary documents. For AI
conversations use `ai_messages` with the appropriate existing scope; inspect the node's
catalog instead of inventing scope ids. `user`/`human` roles map to human; other role values
are preserved, and a missing role defaults to assistant. Normalize roles accurately before
import. Do not label other people's words as the owner's.

`format` is `json`, `jsonl` (also `.ndjson`) or `csv`. CSV field values are strings. A nested
JSON array uses `file_ingest_shape.raw_record_path`, e.g. `items[*]`; mapping paths are then
relative to each item. Paths are dotted keys and `[*]`, not arbitrary JSONPath or code.
Record ids must be present, stable and unique; prefix ids with the source when needed to
avoid collisions across sources. Dates should include their actual time zone.

`posture` is `personal` for owner-authored by construction, `mixed` for mixed authors,
or `ambient` for observed/external information. Choose it from the input's meaning.
Automatic enrichment runs the node's normal processing. `manual` defers derived search
and facts; it is useful for diagnostics but should not silently become the default when
the user wants to ask questions. Neither setting disables the node's privacy pipeline.

## Raw table for an unsupported shape

For `[{"id":"row:one","content":"Synthetic row"}]`:

```json
{
  "source_id": "my_rows",
  "display_name": "My rows",
  "source_type": "file",
  "delivery": "owner_upload",
  "schema_id": "my.rows.v1",
  "parser_id": "my.rows.v1",
  "posture": "mixed",
  "enrichment_trigger": "manual",
  "pipeline_include_data_table": true,
  "tables": [{
    "table_id": "my_rows_data",
    "display_name": "Rows",
    "columns": [
      {"name":"record_id","type":"text","primary_key":true},
      {"name":"content","type":"text"}
    ]
  }],
  "file_ingest_shape": {
    "format":"json",
    "parser_extract_map":{"record_id":"id","content":"content"}
  }
}
```

This stores rows without canonical search or facts. Private raw tables must be named with
the source id as a prefix (dots and hyphens become underscores), followed by `_`; existing
unrelated tables cannot be reused. Confirm the user wants raw-only storage before proceeding
when their request was to make the data available in answers.

## Current limits

Custom JSON extract maps support chat lanes or raw tables. Other canonical lanes can reuse
a compatible bundled parser/schema; a new custom parser for another lane needs adapter
work. Do not reshape invoices, journals or documents as chat just to pass validation.
The preparation command explains unsupported mappings. A JSON definition does not install
Python code, fetch an API, set up OAuth, grant a producer, or schedule a polling job.

Initial files and definitions are each limited to 2 MiB; parser previews check 200 records.
The original sample stays local to the node, but inspecting it in an AI session shares it
with that AI provider, and normal node processing uses the person's configured services.
