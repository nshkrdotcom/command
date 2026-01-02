# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-01

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
