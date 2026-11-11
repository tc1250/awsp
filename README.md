# awsp

Shell wrapper and profile switcher for [`gimme-aws-creds`](https://github.com/Nike-Inc/gimme-aws-creds) and the [AWS CLI](https://aws.amazon.com/cli/).

Works in **Zsh** and **Bash** across any terminal emulator (macOS Terminal.app, iTerm2, VS Code / Cursor terminal, Ghostty, Warp, tmux, etc.) with **no Oh-My-Zsh requirement**.

## Features

- **Profile status at a glance (`awsp`)**: Lists all profiles from `~/.aws/credentials` and `~/.aws/config`, marks your active `AWS_PROFILE`, and calculates remaining token validity (`VALID (42m left)` vs `EXPIRED`) from `x_security_token_expires`.
- **Smart profile switching (`awsp <substring>`)**: Case-insensitive substring matching that automatically prefers **VALID** tokens over **EXPIRED** tokens, and exact matches over partial matches.
- **Okta login integration (`awsp login [target|all]`)**: Discovers Okta targets from `~/.okta_aws_login_config`, runs `gimme-aws-creds` cleanly, and displays updated profile expiration statuses.
- **Safe `gimme-aws-creds` wrapper**: Automatically unsets stale `AWS_PROFILE` / `AWS_DEFAULT_PROFILE` values inside a subshell before invoking `gimme-aws-creds` so `boto3` never crashes with `ProfileNotFound`.
- **AWS SSO support (`awsp login sso [profile]`)**: Auto-detects your SSO profile from `~/.aws/config` (or matches by substring) and runs `aws sso login`.
- **Tab completion**: Built-in Zsh and Bash completion for subcommands, profile names, Okta targets, and SSO profiles.

## Requirements

- **[AWS CLI (`aws`)](https://aws.amazon.com/cli/)**
- **[`gimme-aws-creds`](https://github.com/Nike-Inc/gimme-aws-creds)**
- **Python 3** (uses Python standard library only: `configparser`, `datetime`, `os`, `sys`)
- **Shell**: `zsh` (macOS default) or `bash`

## Installation

### Quick Install

Clone into `~/.awsp` and run `./install.sh`:

```bash
git clone https://github.com/tc1250/awsp.git ~/.awsp
~/.awsp/install.sh
source ~/.zshrc
```

*(If you clone the repository to another directory and run `./install.sh`, it will automatically copy `awsp.sh` into `~/.awsp/awsp.sh` and configure your shell RC file.)*

### Manual Install

Copy `awsp.sh` to `~/.awsp/awsp.sh` and add this line to your `~/.zshrc` (or `~/.bashrc`):

```bash
[ -f "$HOME/.awsp/awsp.sh" ] && source "$HOME/.awsp/awsp.sh"
```

## Usage

```text
Usage:
  awsp                       List all AWS profiles (with expiry) and Okta login targets
  awsp list | ls             Same as running 'awsp' with no arguments
  awsp <substring>           Switch AWS_PROFILE to matching profile (prefers VALID over EXPIRED)
  awsp login                 Log in via gimme-aws-creds (DEFAULT target) and list profiles
  awsp login <okta-target>   Log in to a specific Okta target in ~/.okta_aws_login_config
  awsp login all             Log in to all Okta targets in ~/.okta_aws_login_config
  awsp login sso [profile]   Run 'aws sso login' for an SSO profile (auto-detected if only one)
  awsp - | clear             Unset AWS_PROFILE
```

### Examples

```bash
# List all profiles, token expiration times, and Okta targets
awsp

# Switch AWS_PROFILE by substring (e.g. matches "dev-account-Administrator")
awsp dev

# Refresh credentials for the DEFAULT Okta target
awsp login

# Refresh credentials for a specific Okta login target (substring match supported)
awsp login sandbox

# Refresh all Okta targets defined in ~/.okta_aws_login_config
awsp login all

# Log in via AWS IAM Identity Center (SSO)
awsp login sso

# Clear active AWS_PROFILE
awsp clear
```

## Environment Variables (Optional)

| Variable | Default | Description |
|---|---|---|
| `AWS_SHARED_CREDENTIALS_FILE` | `~/.aws/credentials` | Path to AWS credentials file |
| `AWS_CONFIG_FILE` | `~/.aws/config` | Path to AWS config file |
| `OKTA_AWS_LOGIN_CONFIG` | `~/.okta_aws_login_config` | Path to `gimme-aws-creds` config file |
| `AWSP_DEFAULT_SSO_PROFILE` | *(auto-detected)* | Default profile name for `awsp login sso` when multiple SSO profiles exist |
