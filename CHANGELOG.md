# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Quality Gate Framework** - Enforcement checkpoints for workflow automation pipeline (ADR-0008)
  - `Command.Gates.GateSpec` - Gate specification struct with category, criteria, and retry config
  - `Command.Gates.GateCriterion` - Individual criterion struct with evaluator function and threshold
  - `Command.Gates.Definitions` - 13 gate definitions across DOC (3), IMPL (7), and OPS (3) categories
  - `Command.Gates.Engine` - Gate evaluation engine with telemetry, retry logic, and idempotent evaluation
  - `Command.Gates.Override` - Override workflow with request, approve, reject lifecycle and ETS-backed store
  - `Command.Gates.OverrideRequest` - Override request struct with justification, risk assessment, and decision tracking
  - `Command.Gates.AuthorityMatrix` - Role-based authority matrix for override approval enforcement
  - `Command.Gates.CostCeiling` - GATE-OPS-002 cost ceiling enforcement using Decimal arithmetic
  - `Command.Test.ParityHelper` - Parity test framework with Jaccard similarity and threshold-based evaluation
  - `Command.Test.FixtureHelper` - Test fixture management for JSON, provider responses, and git repos
  - `Command.Test.HTTPMock` - Bypass-based HTTP mocking for Claude and Codex APIs
  - Test fixtures for prompt sets, provider responses (Claude/Codex), normalized events, VCS, and approvals
  - GitHub Actions workflow for quality gate enforcement in CI/CD
  - Gate check script for command-line gate evaluation (`scripts/check_gate.exs`)
  - Override expiration support with configurable duration
  - Telemetry events for gate evaluation, cost ceiling checks, and ceiling exceeded alerts
- `mix command.prompts` Mix task for prompt set execution (ADR-0005)
- `Command.CLI.PromptRunner` for execution orchestration
- `Command.CLI.ProgressDisplay` for TUI/JSON progress output
- `Command.CLI.ConfigLoader` for config file parsing
- `Command.CLI.LegacyAdapter` for run_prompts.exs compatibility
- `Command.CLI.ErrorHandler` for error formatting and recovery hints
- `Command.Progress.FileMirror` for file-based progress compatibility
- Support for --run, --list, --dry-run, --continue commands
- Support for --plan-only and --validate commands
- Support for --provider, --model, --no-commit flags
- Support for --partial-mode, --partial-continue, --force-continue flags
- Support for --repo-override NAME:PATH overrides
- Support for --file-only mode for standalone execution
- TUI spinner and progress bar for interactive execution
- JSON event emission for CI/CD pipelines
- **Prompt Set Schema and Progress Tracking** - Foundational database schema for prompt execution tracking (ADR-0001)
  - `prompt_sets` table for storing prompt set definitions with JSONB config
  - `prompt_set_runs` table for tracking execution instances with aggregate metrics
  - `prompt_step_runs` table for individual prompt execution state and token usage
  - `prompt_changesets` table for prompt/run changeset aggregation (multi-repo support)
  - `prompt_repo_results` table for per-repo execution and commit outcomes
  - `Command.PromptSets.PromptSet` - Schema for prompt set definitions
  - `Command.PromptSets.PromptSetRun` - Schema for execution instances with state machine
  - `Command.PromptSets.PromptStepRun` - Schema for step-level execution tracking
  - `Command.PromptSets.PromptChangeset` - Schema for multi-repo changeset tracking
  - `Command.PromptSets.PromptRepoResult` - Schema for per-repo outcomes with invariant enforcement
  - `Command.PromptSets.StateMachine` - State machine logic for runs and steps
  - `Command.PromptSets` context module with CRUD operations and state transitions
  - Progress state machine for runs: pending -> running -> paused -> completed/partial_success/failed/aborted
  - Progress state machine for steps: pending -> running -> completed/partial_success/failed/skipped
  - Token usage and cost tracking per step with run-level aggregates
  - Resume capability from last completed step with policy-aware resume points
  - Support for `partial_success` as resumable state for multi-repo partial completion
  - Branch strategy support (direct, feature_branch, per_prompt_branch)
  - Database constraints for status/commit_status alignment and invariant enforcement
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
  - `Command.Adapter.Codex` - Codex SDK event normalization with Thread/Turn lifecycle support and struct-based item matching
  - `Command.Adapter.Fallback` - Compatibility mode fallback generation with per-field telemetry
  - `Command.Stream` - Unified stream entry point with optional buffering strategies
  - `Command.AI.Options` - Option layering for provider-specific AI execution (prompt-set defaults → run overrides → prompt overrides) with deep-merge for `claude_opts`, `codex_opts`, `codex_thread_opts`
  - Telemetry events for fallback usage and unknown event types
  - Strict mode (default in production) validates all events before emission
  - Compatibility mode (default in dev/test) generates fallbacks with telemetry warnings
  - Parity tests ensuring structural equivalence across providers
- `Command.FlowStone.Resources.ProgressTracker` - Pipeline execution progress tracking (DB-backed)
- `Command.FlowStone.Resources.ArtifactStore` - Filesystem-based artifact storage with run isolation
- `Command.FlowStone.Resources.AgentRunner` - LLM provider abstraction implementing FlowStone.Resource behaviour
- `Command.FlowStone.Resources.ResourceSetup` - FlowStone resource registration helper
- `Command.FlowStone.Resources.VCS` - FlowStone resource for VCS context injection
  - Configurable adapter with default to Git CLI
  - Convenience functions delegating to adapter for all VCS operations
  - Health check validates repository existence
- `Command.Steps.Git` - FlowStone step handlers for VCS operations (ADR-0004)
  - `:status` operation returns repository status map
  - `:commit` operation stages all, commits, returns hash (or :no_changes for clean repos)
  - `:diff` operation supports both ref comparison and uncommitted diff
  - Resource extraction from FlowStone context
- Telemetry instrumentation for VCS operations via `[:portfolio, :vcs, :*]` events

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
