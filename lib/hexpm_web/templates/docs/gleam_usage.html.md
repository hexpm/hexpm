## Usage

### Installation

[Install Gleam](https://gleam.run/getting-started/installing/).

### Defining dependencies

Hex packages requirements are specified in `gleam.toml` in the `dependencies` and `dev-dependencies` tables.

```toml
[dependencies]
gleam_stdlib = ">= 0.60.0 and < 2.0.0"
gleam_time = ">= 1.3.0 and < 2.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0"
```

Dependencies requirements can also be added with the `gleam add lustre@4` terminal command.

### Fetching dependencies

Gleam will automatically download the missing required dependencies when running any command that needs them, such as `gleam run` or `gleam test`.
