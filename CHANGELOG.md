# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Artifact Provenance Storage** - Content-addressable storage with lineage tracking (ADR-0006)
  - `Command.Artifacts.Hash` - SHA-256 hash computation for artifact integrity verification
  - `Command.Artifacts.ContentStore` - Content-addressable storage (CAS) for automatic deduplication
  - `Command.Lineage.ProvenanceEdge` - Schema for provenance relationships (implements, created_by, step_of, etc.)
  - `Command.Lineage.Edges` - Provenance edge recording and querying
  - `Command.Lineage.Graph` - Lineage graph construction and traversal (ancestors, descendants, shortest path)
  - `Command.Artifacts.RetentionWorker` - Background worker for soft-deleting expired artifacts
  - `Command.Artifacts.PurgeWorker` - Background worker for hard-deleting expired artifacts after grace period
  - `Command.Artifacts.CasGcWorker` - Background worker for garbage collecting unreferenced CAS content
  - Database migrations for `artifacts` table and `lineage.provenance_edges` table
  - 11 relationship types for complete lineage tracking
  - Automatic deduplication of prompts, responses, diffs, and other artifact types
  - Streaming hash computation for large files (64KB chunks)
  - Graph traversal with cycle detection and depth limits
  - Relationship filtering for targeted provenance queries
- **Provider Normalization Layer** - Unified event schema for multi-provider agent interactions
  - `Command.Event` - Unified event struct with 12 event types (`:message_start`, `:text_delta`, `:message_stop`, `:tool_use_start`, `:tool_use_delta`, `:tool_use_end`, `:tool_result`, `:file_change`, `:structured_output`, `:reasoning`, `:usage_update`, `:error`) plus `:raw` fallback
  - `Command.Adapter` - Behaviour for provider stream adapters with `normalize_stream/2`, `normalize_event/2`, and `supports_event?/1` callbacks
  - `Command.Adapter.Validation` - Event schema validation with strict/compatibility mode support
  - `Command.Adapter.Claude` - Claude Agent SDK event normalization with tool input accumulation and error mapping
  - `Command.Adapter.Codex` - Codex SDK event normalization with Thread/Turn lifecycle support
  - `Command.Stream` - Unified stream entry point with optional buffering strategies
  - Telemetry events for fallback usage and unknown event types
  - Strict mode (default in production) validates all events before emission
  - Compatibility mode (default in dev/test) generates fallbacks with telemetry warnings
  - Parity tests ensuring structural equivalence across providers
- `Command.FlowStone.Resources.ProgressTracker` - Pipeline execution progress tracking (DB-backed)
- `Command.FlowStone.Resources.ArtifactStore` - Filesystem-based artifact storage with run isolation
- `Command.FlowStone.Resources.AgentRunner` - LLM provider abstraction implementing FlowStone.Resource behaviour
- `Command.FlowStone.Resources.ResourceSetup` - FlowStone resource registration helper

## [0.1.0] - 2025-01-02

### Added

- Initial release of Command core library
- User management with API credential storage
- Session management with branching support
- Agent call tracking for multiple LLM providers
- Tool use tracking with approval workflows
- Workflow definitions and execution tracking
- RAG index management with pgvector support
- Approval items and auto-approval rules
- Versioned artifact storage
- Cost tracking with daily summaries
- Scheduled job management
- User presence and activity logging
- Comprehensive test suite
- Full documentation

### Database Schema

- 19 migrations creating 21 tables
- PostgreSQL extensions: citext, pg_trgm, btree_gin, vector
- UUID primary keys throughout
- pgvector HNSW index for similarity search
