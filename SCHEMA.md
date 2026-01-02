# Command Database Schema

## Overview

19 migrations, 21 tables covering:

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
│                              USERS & AUTH                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  users ────────────────┬──────────────────────────────────────────────┐    │
│    │                   │                                              │    │
│    │                   ▼                                              │    │
│    │            api_credentials                                       │    │
│    │                                                                  │    │
├────┴──────────────────────────────────────────────────────────────────┴────┤
│                            SESSIONS & MESSAGES                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  sessions ◄──────┐ (self-ref: parent_session_id for branching)             │
│    │             │                                                          │
│    │             │                                                          │
│    ├─────────────┼──────────► messages                                     │
│    │             │               │                                          │
│    │             │               ├──► agent_calls                          │
│    │             │               │       │                                  │
│    │             │               │       └──► tool_uses                    │
│    │             │               │               │                          │
│    │             │               │               └──► approval_items       │
│    │             │               │                                          │
├────┴─────────────┴───────────────┴──────────────────────────────────────────┤
│                              WORKFLOWS                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  workflows ──────────────────────► workflow_runs                           │
│    │                                    │                                   │
│    │ (forked_from_id)                   │                                   │
│    │                                    ▼                                   │
│    │                             workflow_steps ──► agent_calls            │
│    │                                    │                                   │
│    │                                    └──► approval_items                │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                              RAG / INDEXES                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  indexes ─────────────────┬──────► context_documents                       │
│                           │              │                                  │
│                           │              ▼                                  │
│                           └──────► context_chunks (with pgvector)          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                           COST & SCHEDULING                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  cost_records ──────────► cost_daily_summaries                             │
│                                                                             │
│  scheduled_jobs                                                             │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                         PRESENCE & ACTIVITY                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  presence_records (real-time, complements Phoenix.Presence)                │
│                                                                             │
│  activity_logs (audit trail)                                               │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                              ARTIFACTS                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  artifacts ◄────────┐ (self-ref: previous_version_id for versioning)       │
│                     │                                                       │
│                     │ (diff_base_artifact_id for diffs)                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Table Purposes

| Table | Purpose |
|-------|---------|
| `users` | User accounts, preferences, multi-user support |
| `api_credentials` | Encrypted API keys for LLM providers |
| `sessions` | Persistent agent work contexts, branchable |
| `messages` | Conversation history within sessions |
| `agent_calls` | Individual LLM API calls with full tracking |
| `tool_uses` | Tool invocations with approval workflow |
| `workflows` | Reusable workflow definitions (DAGs) |
| `workflow_runs` | Instances of workflow executions |
| `workflow_steps` | Individual step executions within runs |
| `indexes` | RAG index configurations |
| `context_documents` | Source documents for RAG |
| `context_chunks` | Embedded chunks with pgvector |
| `approval_items` | HITL approval queue |
| `approval_rules` | Auto-approval patterns |
| `artifacts` | Files, outputs, diffs, versioned assets |
| `cost_records` | Detailed cost tracking per API call |
| `cost_daily_summaries` | Aggregated daily cost reports |
| `scheduled_jobs` | Workflow and task scheduling |
| `presence_records` | Multi-user presence in sessions |
| `activity_logs` | Audit trail for all actions |

## Extensions Required

- `citext` - Case-insensitive text for emails
- `pg_trgm` - Trigram matching for search
- `btree_gin` - GIN index support
- `vector` - pgvector for embeddings

## Key Design Decisions

1. **UUIDs everywhere** - Distributed-friendly, no sequence contention
2. **Flexible `:map` fields** - JSONB for evolving schemas (git_context, metadata, etc.)
3. **Denormalized stats** - Sessions track total_cost_cents, workflows track run_count
4. **Branching support** - Sessions can fork, artifacts can version
5. **Multi-user native** - presence_records, activity_logs from day 1
6. **Cost tracking** - Every API call tracked, daily summaries for reporting
7. **pgvector built-in** - RAG with HNSW index for similarity search

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
18 - deferred foreign keys
```

## Next Steps

1. Generate Ecto schemas from these migrations
2. Add Oban for background job processing (pairs with scheduled_jobs)
3. Implement Phoenix.Presence integration with presence_records
4. Build the LiveView UI on top of this schema
