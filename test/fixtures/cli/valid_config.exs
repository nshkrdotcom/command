%{
  project_dir: "/home/user/projects/test",
  prompts_file: Path.join(__DIR__, "prompts.txt"),
  commit_messages_file: Path.join(__DIR__, "commit-messages.txt"),
  progress_file: ".progress",
  log_dir: "logs",
  model: "claude-sonnet-4-20250514",
  allowed_tools: ["Read", "Write", "Edit", "Glob", "Grep", "Bash"],
  permission_mode: :accept_edits,
  log_mode: :compact,
  log_meta: :none,
  events_mode: :compact,
  phase_names: %{
    1 => "Foundation",
    2 => "Implementation"
  }
}
