# rust-v1

Preset for Rust projects built with Cargo.

| | |
| --- | --- |
| Setup | Stable toolchain with `clippy` and `rustfmt`, plus the Cargo build cache |
| Checks | `cargo fmt --check`, `cargo build`, `cargo clippy -D warnings`, `cargo test`, on all targets |
| Agent tools | `cargo`, except `cargo run` and `cargo publish` |
| Protected paths | `clippy.toml`, `rustfmt.toml`, `rust-toolchain(.toml)` and their dotted variants |
| Never committed | `target` |

## Use it

```yaml
# .github/peppec.yml
preset: rust-v1
```

Any value of [`preset.yml`](preset.yml) can be overridden in `.github/peppec.yml`.

## Limits

- The toolchain is always `stable`: a `rust-toolchain.toml` in the project is not read yet.
- No system packages or services are installed.
