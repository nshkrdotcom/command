# Command Database Schema

## Overview

17 migrations, 21 tables covering:

- **Users & Auth**: users, api_credentials
- **Sessions & Messages**: sessions, messages
- **Agent Execution**: agent_calls, tool_uses
- **Workflows**: workflows, workflow_runs, workflow_steps
- **RAG/Indexes**: indexes, context_documents, context_chunks
- **Approvals**: approval_items, approval_rules
- **Artifacts**: artifacts
- **Cost Tracking**: cost_records, cost_daily_summaries
- **Scheduling**: scheduled_jobs
- **Presence & Audit**: presence_records, activity_logs

## Entity Relationship Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USERS & AUTH                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  users ────────────────┬──────────────────────────────────────────────┐     │
│    │                   │                                              │     │
│    │                   ▼                                              │     │
│    │            api_credentials                                       │     │
│    │                                                                  │     │
├────┴──────────────────────────────────────────────────────────────────┴─────┤
│                            SESSIONS & MESSAGES                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  sessions ◄──────┐ (self-ref: parent_session_id for branching)              │
│    │             │                                                          │
│    │             │                                                          │
│    ├─────────────┼──────────► messages                                      │
│    │             │               │                                          │
│    │             │               ├──► agent_calls                           │
│    │             │               │       │                                  │
│    │             │               │       └──► tool_uses                     │
│    │             │               │               │                          │
│    │             │               │               └──► approval_items        │
│    │             │               │                                          │
├────┴─────────────┴───────────────┴──────────────────────────────────────────┤
│                              WORKFLOWS                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  workflows ──────────────────────► workflow_runs                            │
│    │                                    │                                   │
│    │ (forked_from_id)                   │                                   │
│    │                                    ▼                                   │
│    │                             workflow_steps ──► agent_calls             │
│    │                                    │                                   │
│    │                                    └──► approval_items                 │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                              RAG / INDEXES                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  indexes ─────────────────┬──────► context_documents                        │
│                           │              │                                  │
│                           │              ▼                                  │
│                           └──────► context_chunks (with pgvector)           │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                           COST & SCHEDULING                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  cost_records ──────────► cost_daily_summaries                              │
│                                                                             │
│  scheduled_jobs                                                             │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                         PRESENCE & ACTIVITY                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  presence_records (real-time, complements Phoenix.Presence)                 │
│                                                                             │
│  activity_logs (audit trail)                                                │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                              ARTIFACTS                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  artifacts ◄────────┐ (self-ref: previous_version_id for versioning)        │
│                     │                                                       │
│                     │ (diff_base_artifact_id for diffs)                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Extensions Required

- `citext` - Case-insensitive text for emails
- `pg_trgm` - Trigram matching for full-text search
- `btree_gin` - GIN index support
- `vector` - pgvector for embeddings (HNSW indexing)

## Table Details

### users

User accounts with multi-auth support and encrypted API key storage.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| email | citext | Unique email address |
| name | string | Display name |
| avatar_url | string | Profile image URL |
| auth_provider | string | "local", "github", "google" |
| auth_uid | string | External provider UID |
| password_hash | string | For local auth |
| preferences | jsonb | User preferences |
| api_keys | jsonb | Legacy API key storage (encrypted) |
| status | string | "active", "inactive", "suspended" |

### api_credentials

Encrypted storage for provider API keys.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner reference |
| name | string | User-friendly name |
| provider | string | "anthropic", "openai", "google", "github" |
| encrypted_key | binary | Cloak-encrypted API key |
| key_hint | string | Last 4 chars for identification |
| status | string | "active", "revoked", "expired" |
| last_validated_at | timestamp | Last validation check |
| last_used_at | timestamp | Last API call |
| use_count | integer | Total usage count |
| scopes | string[] | Provider permissions |
| expires_at | timestamp | Key expiration |

### sessions

Persistent agent work contexts with branching support.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner reference |
| name | string | Session name (required) |
| purpose | text | Session goal/description |
| slug | string | URL-friendly identifier |
| status | string | "active", "paused", "completed", "archived" |
| parent_session_id | uuid | For forked sessions |
| forked_at_message_id | uuid | Fork point reference |
| message_count | integer | Denormalized count |
| total_tokens_in | bigint | Denormalized total |
| total_tokens_out | bigint | Denormalized total |
| total_cost_cents | integer | Denormalized cost |
| total_duration_ms | bigint | Denormalized duration |
| default_agent | string | "claude", "codex", "gemini" |
| default_model | string | Model identifier |
| system_prompt | text | Default system prompt |
| temperature | float | Default temperature |
| max_tokens | integer | Default max tokens |
| linked_index_ids | uuid[] | RAG index links |
| linked_workflow_ids | uuid[] | Workflow links |
| metadata | jsonb | Flexible metadata |
| tags | string[] | Categorization tags |
| git_context | jsonb | Repo/branch/commit info |

### messages

Conversation history within sessions.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| session_id | uuid | Parent session |
| role | string | "user", "assistant", "system", "tool_result" |
| content | text | Message text |
| content_blocks | jsonb[] | Multi-part content |
| sequence | integer | Order in session |
| agent_call_id | uuid | Linked agent call |
| tool_use_id | uuid | Linked tool use |
| visible_in_branches | uuid[] | Branch visibility |
| token_count | integer | Token estimate |
| attachments | jsonb[] | File/image refs |
| metadata | jsonb | Flexible metadata |

**Indexes**: Full-text search on content using GIN.

### agent_calls

Individual LLM API calls with complete lifecycle tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| session_id | uuid | Parent session |
| user_id | uuid | Initiating user |
| provider | string | "anthropic", "openai", "google" |
| model | string | Model identifier |
| status | string | "pending", "streaming", "completed", "failed", "cancelled", "timeout" |
| prompt_messages | jsonb[] | Full messages array |
| system_prompt | text | System prompt used |
| response_content | text | Response text |
| response_blocks | jsonb[] | Structured response |
| stop_reason | string | "end_turn", "tool_use", "max_tokens" |
| tokens_in | integer | Input tokens |
| tokens_out | integer | Output tokens |
| cache_tokens_read | integer | Cache read tokens |
| cache_tokens_write | integer | Cache write tokens |
| cost_cents | integer | Calculated cost |
| started_at | timestamp | Call start |
| first_token_at | timestamp | Time to first token |
| completed_at | timestamp | Call completion |
| duration_ms | integer | Total duration |
| temperature | float | Temperature used |
| max_tokens | integer | Max tokens setting |
| tools_provided | string[] | Available tool names |
| error_type | string | Error classification |
| error_message | text | Error details |
| retry_count | integer | Retry attempts |
| workflow_run_id | uuid | Workflow link |
| workflow_step_id | uuid | Step link |
| metadata | jsonb | Flexible metadata |

### tool_uses

Tool invocations with approval workflow.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| agent_call_id | uuid | Parent agent call |
| session_id | uuid | Parent session |
| tool_name | string | "bash", "write_file", "read_file" |
| tool_use_id | string | LLM-provided ID |
| input | jsonb | Tool input parameters |
| output | text | Tool output |
| output_truncated | boolean | Output was truncated |
| status | string | "pending", "approved", "denied", "executing", "completed", "failed", "timeout" |
| requires_approval | boolean | HITL required |
| approval_id | uuid | Linked approval item |
| approved_by_id | uuid | Approving user |
| approved_at | timestamp | Approval time |
| denial_reason | text | Denial explanation |
| started_at | timestamp | Execution start |
| completed_at | timestamp | Execution end |
| duration_ms | integer | Execution duration |
| file_changes | jsonb[] | File operation details |
| exit_code | integer | Shell exit code |
| stdout | text | Shell stdout |
| stderr | text | Shell stderr |
| error_type | string | Error classification |
| error_message | text | Error details |
| sequence | integer | Order in agent call |
| metadata | jsonb | Flexible metadata |

### workflows

Reusable workflow definitions (DAGs).

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| name | string | Workflow name |
| slug | string | URL identifier (unique per user) |
| description | text | Workflow description |
| version | integer | Version number |
| status | string | "draft", "active", "deprecated", "archived" |
| is_template | boolean | Can be forked |
| forked_from_id | uuid | Source workflow |
| steps | jsonb[] | Step definitions |
| input_schema | jsonb | Required inputs |
| output_schema | jsonb | Expected outputs |
| default_config | jsonb | Default settings |
| triggers | jsonb[] | Schedule/webhook triggers |
| run_count | integer | Denormalized total |
| success_count | integer | Denormalized successes |
| failure_count | integer | Denormalized failures |
| avg_duration_ms | bigint | Average duration |
| avg_cost_cents | integer | Average cost |
| tags | string[] | Categories |
| category | string | Primary category |
| metadata | jsonb | Flexible metadata |

### workflow_runs

Instances of workflow executions.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| workflow_id | uuid | Parent workflow |
| user_id | uuid | Executing user |
| session_id | uuid | Optional session link |
| workflow_snapshot | jsonb | Frozen workflow definition |
| status | string | "pending", "running", "paused", "waiting_approval", "completed", "failed", "cancelled", "timeout" |
| input | jsonb | Run inputs |
| output | jsonb | Run outputs |
| current_step_id | string | Active step |
| completed_step_ids | string[] | Finished steps |
| failed_step_id | string | Failed step |
| started_at | timestamp | Run start |
| completed_at | timestamp | Run end |
| duration_ms | bigint | Total duration |
| total_tokens_in | bigint | Aggregate tokens |
| total_tokens_out | bigint | Aggregate tokens |
| total_cost_cents | integer | Aggregate cost |
| trigger_type | string | "manual", "schedule", "webhook", "api" |
| trigger_metadata | jsonb | Trigger details |
| error_type | string | Error classification |
| error_message | text | Error details |
| error_step_id | string | Error location |
| git_context | jsonb | Git state at run |
| retry_of_run_id | uuid | Retry source |
| retry_count | integer | Retry attempts |
| metadata | jsonb | Flexible metadata |

### workflow_steps

Individual step executions within runs.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| workflow_run_id | uuid | Parent run |
| step_id | string | Step identifier |
| step_name | string | Step display name |
| step_type | string | "agent_call", "rag_query", "shell", "approval", "python" |
| step_config | jsonb | Frozen step config |
| status | string | "pending", "running", "waiting_approval", "completed", "failed", "skipped", "timeout" |
| input | jsonb | Step inputs |
| output | jsonb | Step outputs |
| agent_call_id | uuid | Linked agent call |
| approval_id | uuid | Linked approval |
| started_at | timestamp | Step start |
| completed_at | timestamp | Step end |
| duration_ms | integer | Step duration |
| tokens_in | integer | Token usage |
| tokens_out | integer | Token usage |
| cost_cents | integer | Step cost |
| error_type | string | Error classification |
| error_message | text | Error details |
| attempt_number | integer | Current attempt |
| max_attempts | integer | Max retries |
| sequence | integer | Execution order |
| depends_on | string[] | Dependency IDs |
| metadata | jsonb | Flexible metadata |

### indexes

RAG index configurations.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| name | string | Index name |
| slug | string | URL identifier (unique per user) |
| description | text | Index description |
| status | string | "creating", "ready", "updating", "failed", "archived" |
| source_type | string | "local_repo", "github", "files", "url" |
| source_config | jsonb | Source settings |
| chunk_strategy | string | "fixed", "semantic", "code_aware" |
| chunk_config | jsonb | Chunking settings |
| embedding_provider | string | "openai", "cohere", "local" |
| embedding_model | string | Model identifier |
| embedding_dimensions | integer | Vector dimensions (default 1536) |
| storage_backend | string | "pgvector", "weaviate", "qdrant" |
| storage_config | jsonb | Backend settings |
| document_count | integer | Total documents |
| chunk_count | integer | Total chunks |
| total_tokens | bigint | Total tokens |
| embedding_cost_cents | integer | Embedding cost |
| last_indexed_at | timestamp | Last index time |
| indexing_started_at | timestamp | Indexing start |
| indexing_duration_ms | bigint | Indexing duration |
| last_error | text | Error details |
| auto_reindex | boolean | Auto-reindex enabled |
| reindex_schedule | string | Cron expression |
| last_reindex_at | timestamp | Last reindex |
| tracked_commit | string | Last indexed commit |
| git_config | jsonb | Git settings |
| tags | string[] | Categories |
| metadata | jsonb | Flexible metadata |

### context_documents

Source documents for RAG indexes.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| index_id | uuid | Parent index |
| uri | string | Unique resource identifier |
| title | string | Document title |
| source_type | string | "file", "url", "github", "api" |
| content_hash | string | SHA256 for change detection |
| size_bytes | bigint | File size |
| mime_type | string | Content type |
| language | string | Programming language |
| encoding | string | Text encoding |
| git_commit | string | Git commit SHA |
| git_branch | string | Git branch |
| chunked_at | timestamp | Last chunking |
| chunk_count | integer | Number of chunks |
| total_tokens | integer | Total token count |
| processing_error | text | Processing error |
| metadata | jsonb | Flexible metadata |

**Indexes**: Unique on (index_id, uri).

### context_chunks

Embedded chunks with pgvector support.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| index_id | uuid | Parent index |
| source_uri | string | Source document URI |
| source_type | string | "file", "url", "github", "api" |
| source_metadata | jsonb | Source details |
| content | text | Chunk text content |
| content_hash | string | For deduplication |
| chunk_index | integer | Order in document |
| start_offset | integer | Character offset |
| end_offset | integer | Character offset |
| start_line | integer | Line number |
| end_line | integer | Line number |
| token_count | integer | Token count |
| embedding | vector(1536) | pgvector embedding |
| embedding_model | string | Model used |
| embedded_at | timestamp | Embedding time |
| language | string | Programming language |
| code_context | jsonb | Module/function info |
| metadata | jsonb | Flexible metadata |

**Indexes**: HNSW index on embedding for cosine similarity search.

### approval_items

Human-in-the-loop approval queue.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| session_id | uuid | Session context |
| approval_type | string | "tool_use", "file_write", "shell_command", "workflow_step", "custom" |
| status | string | "pending", "approved", "denied", "expired", "auto_approved" |
| priority | string | "low", "normal", "high", "critical" |
| title | string | Request summary |
| description | text | Detailed explanation |
| payload | jsonb | Data being approved |
| source_type | string | "tool_use", "workflow_step", "manual" |
| source_id | uuid | Source reference |
| context | jsonb | Reviewer context |
| risk_level | string | "low", "medium", "high", "critical" |
| risk_factors | string[] | Risk indicators |
| decided_by_id | uuid | Decision maker |
| decided_at | timestamp | Decision time |
| decision_note | text | Decision explanation |
| modified_payload | jsonb | Reviewer modifications |
| expires_at | timestamp | Expiration time |
| timeout_action | string | "deny", "approve", "escalate" |
| auto_approval_rule_id | uuid | Matched rule |
| auto_approval_reason | string | Auto-approval explanation |
| notified_at | timestamp | Notification time |
| notification_channels | string[] | Notification methods |
| metadata | jsonb | Flexible metadata |

### approval_rules

Auto-approval rule definitions.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| name | string | Rule name |
| description | text | Rule description |
| status | string | "active", "disabled" |
| approval_type | string | "tool_use", "file_write", "shell_command", "*" |
| tool_names | string[] | Specific tools (empty = all) |
| conditions | jsonb | Match conditions |
| action | string | "approve", "deny", "require_review" |
| action_note | string | Auto-decision note |
| max_auto_approvals_per_hour | integer | Hourly limit |
| max_auto_approvals_per_session | integer | Session limit |
| current_hour_count | integer | Current usage |
| hour_reset_at | timestamp | Counter reset time |
| priority | integer | Rule priority (higher = first) |
| times_triggered | integer | Usage count |
| last_triggered_at | timestamp | Last match |
| applies_to_sessions | uuid[] | Session scope |
| applies_to_workflows | uuid[] | Workflow scope |
| metadata | jsonb | Flexible metadata |

### artifacts

Versioned files, outputs, and diffs.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| session_id | uuid | Session context |
| name | string | Artifact name |
| description | text | Artifact description |
| artifact_type | string | "file", "code", "diff", "image", "document", "archive", "other" |
| mime_type | string | Content type |
| storage_backend | string | "local", "s3", "inline" |
| storage_path | string | Local/S3 path |
| storage_key | string | S3 key |
| inline_content | binary | Direct storage |
| size_bytes | bigint | File size |
| checksum | string | SHA256 hash |
| original_filename | string | Original name |
| language | string | Programming language |
| line_count | integer | Lines of code |
| source_type | string | "agent_output", "tool_result", "upload", "workflow" |
| source_id | uuid | Source reference |
| version | integer | Version number |
| previous_version_id | uuid | Previous version link |
| is_latest | boolean | Latest version flag |
| git_commit | string | Git commit |
| git_repo | string | Git repository |
| git_path | string | File path in repo |
| diff_base_artifact_id | uuid | Diff base |
| diff_content | text | Diff text |
| additions | integer | Lines added |
| deletions | integer | Lines removed |
| visibility | string | "private", "shared", "public" |
| shared_with_user_ids | uuid[] | Shared users |
| expires_at | timestamp | Expiration |
| retention_policy | string | "permanent", "session", "temporary" |
| tags | string[] | Categories |
| metadata | jsonb | Flexible metadata |

### cost_records

Detailed cost tracking per API call.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| source_type | string | "agent_call", "embedding", "tool_execution" |
| source_id | uuid | Source reference |
| session_id | uuid | Session context |
| workflow_run_id | uuid | Workflow context |
| provider | string | "anthropic", "openai", "google", "cohere" |
| service | string | "chat", "embedding", "image", "speech" |
| model | string | Model identifier |
| tokens_in | integer | Input tokens |
| tokens_out | integer | Output tokens |
| cache_tokens_read | integer | Cache read tokens |
| cache_tokens_write | integer | Cache write tokens |
| units | decimal | Non-token units |
| unit_type | string | Unit description |
| cost_cents | integer | Cost in cents |
| price_per_million_in | integer | Input pricing |
| price_per_million_out | integer | Output pricing |
| incurred_at | timestamp | Cost time |
| day | date | Aggregation bucket |
| metadata | jsonb | Flexible metadata |

### cost_daily_summaries

Aggregated daily cost reports.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| day | date | Summary date (unique per user) |
| total_cost_cents | integer | Daily total |
| total_tokens_in | bigint | Daily input tokens |
| total_tokens_out | bigint | Daily output tokens |
| total_requests | integer | Daily request count |
| cost_by_provider | jsonb | Provider breakdown |
| cost_by_model | jsonb | Model breakdown |
| cost_by_session | jsonb | Session breakdown |

### scheduled_jobs

Workflow and task scheduling.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Owner |
| job_type | string | "workflow", "reindex", "cleanup", "custom" |
| job_config | jsonb | Job parameters |
| schedule_type | string | "once", "cron", "interval" |
| cron_expression | string | Cron schedule |
| interval_seconds | integer | Interval schedule |
| run_at | timestamp | One-time schedule |
| timezone | string | Timezone (default UTC) |
| status | string | "active", "paused", "completed", "failed", "cancelled" |
| last_run_at | timestamp | Last execution |
| last_run_status | string | Last result |
| last_run_error | text | Last error |
| next_run_at | timestamp | Next scheduled |
| run_count | integer | Total runs |
| success_count | integer | Successful runs |
| failure_count | integer | Failed runs |
| max_runs | integer | Run limit |
| expires_at | timestamp | Job expiration |
| allow_concurrent | boolean | Concurrent execution |
| currently_running | boolean | Active execution |
| retry_on_failure | boolean | Retry enabled |
| max_retries | integer | Retry limit |
| retry_delay_seconds | integer | Retry delay |
| notify_on_failure | boolean | Failure notifications |
| notify_on_success | boolean | Success notifications |
| notification_channels | string[] | Notification methods |
| metadata | jsonb | Flexible metadata |

### presence_records

Multi-user presence tracking (complements Phoenix.Presence).

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Present user |
| resource_type | string | "session", "workflow_run", "approval_item" |
| resource_id | uuid | Resource reference |
| status | string | "viewing", "editing", "idle", "away" |
| client_id | string | Browser tab identifier (unique) |
| device_type | string | "desktop", "mobile", "tablet" |
| user_agent | string | Browser info |
| cursor_state | jsonb | Cursor/selection state |
| joined_at | timestamp | Join time |
| last_seen_at | timestamp | Last heartbeat |
| left_at | timestamp | Leave time |
| metadata | jsonb | Flexible metadata |

### activity_logs

Audit trail for all user actions.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | Acting user |
| action | string | Action identifier (see valid actions) |
| resource_type | string | Affected resource type |
| resource_id | uuid | Affected resource |
| details | jsonb | Action details |
| session_id | uuid | Session context |
| client_id | string | Client identifier |
| ip_address | string | Client IP |
| occurred_at | timestamp | Action time |

**Valid Actions**:
- Session: `session.create`, `session.update`, `session.archive`, `session.fork`
- Message: `message.create`, `message.delete`
- Agent: `agent.call.start`, `agent.call.complete`, `agent.call.fail`
- Tool: `tool.execute`, `tool.approve`, `tool.deny`
- Workflow: `workflow.create`, `workflow.run.start`, `workflow.run.complete`, `workflow.run.fail`
- Index: `index.create`, `index.update`, `index.delete`
- Approval: `approval.create`, `approval.approve`, `approval.deny`, `approval.expire`
- Artifact: `artifact.create`, `artifact.update`, `artifact.delete`
- User: `user.login`, `user.logout`, `user.update`

## Key Design Decisions

1. **UUIDs everywhere** - Distributed-friendly, no sequence contention
2. **Flexible JSONB fields** - Evolving schemas (git_context, metadata, config)
3. **Denormalized stats** - Sessions track total_cost_cents, workflows track run_count
4. **Branching support** - Sessions can fork, artifacts can version
5. **Multi-user native** - Presence and activity tracking from day 1
6. **Cost tracking** - Every API call tracked with daily rollups
7. **pgvector built-in** - RAG with HNSW index for similarity search
8. **Full-text search** - GIN indexes on message content
9. **Encrypted credentials** - API keys stored with Cloak encryption

## Migration Order

```
00 - enable_extensions (citext, pg_trgm, btree_gin)
01 - users
02 - sessions
03 - messages
04 - agent_calls
05 - tool_uses
06 - workflows
07 - workflow_runs
08 - workflow_steps
09 - indexes
10 - approval_items
11 - artifacts
12 - approval_rules
13 - cost_records + cost_daily_summaries
14 - api_credentials
15 - scheduled_jobs
16 - presence_records + activity_logs
17 - context_chunks + context_documents (pgvector)
```
