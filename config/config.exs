use Mix.Config

if Mix.env == :test do
  log_level = :notice
else
  log_level = :info
end

config :lager,
  handlers: [
    lager_console_backend:
      [log_level, {:lager_default_formatter, [:time, ' [', :severity, '] ', :message, '\n']}]
  ],
  crash_log: :undefined,
  error_logger_hwm: 150

config :stout,
  truncation_size: 4096,
  level: log_level
