[
  lager: [
    handlers: [
      lager_console_backend:
        [:notice, {:lager_default_formatter, [:time, ' [', :severity, '] ', :message, '\n']}]
      ],
    crash_log: :undefined,
    error_logger_hwm: 150
  ],
  stout: [
    truncation_size: 4096,
    level: :notice
  ]
]
