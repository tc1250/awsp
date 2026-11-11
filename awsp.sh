# shellcheck shell=bash
# awsp — Zero-dependency AWS profile switcher & gimme-aws-creds / AWS SSO helper.
# Compatible with Zsh and Bash (no Oh-My-Zsh or custom terminal required).
#
# Usage: source /path/to/awsp.sh

# gimme-aws-creds resolves AWS_PROFILE via boto3; a stale value fails the run
# with ProfileNotFound before it ever reaches STS.
gimme-aws-creds() {
  ( unset AWS_PROFILE AWS_DEFAULT_PROFILE; command gimme-aws-creds "$@" )
}

# One-stop AWS credential & profile manager:
#   awsp | awsp list | awsp ls -> list AWS profiles (with expiry) + Okta login targets
#   awsp <substring>           -> switch AWS_PROFILE (prefers VALID tokens over EXPIRED)
#   awsp login [okta-target]   -> run gimme-aws-creds (or aws sso login) and list profiles
#   awsp login all             -> refresh all Okta targets sequentially and list profiles
#   awsp - | awsp clear        -> unset AWS_PROFILE
#   awsp -h | --help | help    -> show usage
_awsp_list() {
  local creds="${1:-${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}}"
  local cfg="${2:-${AWS_CONFIG_FILE:-$HOME/.aws/config}}"
  local okta_cfg="${3:-${OKTA_AWS_LOGIN_CONFIG:-$HOME/.okta_aws_login_config}}"

  python3 - "$creds" "$cfg" "$okta_cfg" "${AWS_PROFILE:-}" <<'PY'
import configparser, datetime, os, sys

creds_path, cfg_path, okta_path, current = sys.argv[1:5]
now = datetime.datetime.now(datetime.timezone.utc)
local_now = datetime.datetime.now().strftime("%H:%M:%S")

cp = configparser.RawConfigParser()
if os.path.exists(creds_path):
    cp.read(creds_path)

rows = []
for section in cp.sections():
    exp = cp.get(section, "x_security_token_expires", fallback=None)
    if exp:
        try:
            dt = datetime.datetime.fromisoformat(exp)
            rem = int((dt - now).total_seconds() // 60)
            status = f"VALID ({rem}m left)" if rem > 0 else "EXPIRED"
        except Exception:
            status = exp
    else:
        status = "static/default"
    mark = "*" if section == current else " "
    rows.append((mark, section, status))

cfg = configparser.RawConfigParser()
if os.path.exists(cfg_path):
    cfg.read(cfg_path)
for section in cfg.sections():
    if section.startswith("profile "):
        name = section.split("profile ", 1)[1]
        if not cp.has_section(name):
            mark = "*" if name == current else " "
            rows.append((mark, name, "SSO profile (awsp login sso)"))

active_label = current if current else "(unset)"
print(f"Active AWS_PROFILE: {active_label}  (checked at {local_now})")
print("AWS Profiles (~/.aws/credentials & ~/.aws/config):")
if not rows:
    print("  (none)")
else:
    w = max(len(r[1]) for r in rows)
    for mark, name, status in rows:
        print(f" {mark} {name:<{w}}  {status}")

if os.path.exists(okta_path):
    ocp = configparser.RawConfigParser()
    ocp.read(okta_path)
    targets = ["DEFAULT"] + ocp.sections()
    print("\nOkta Login Targets (run: awsp login [target]):")
    print("   " + ", ".join(targets))
PY
}

_awsp_resolve_sso_profile() {
  local cfg="$1"
  local creds="$2"
  local query="${3:-}"
  python3 - "$cfg" "$creds" "$query" "${AWSP_DEFAULT_SSO_PROFILE:-}" "${AWS_PROFILE:-}" <<'PY'
import configparser, os, sys

cfg_path, creds_path, query, default_sso, active_prof = sys.argv[1:6]

cfg = configparser.RawConfigParser()
if os.path.exists(cfg_path):
    cfg.read(cfg_path)

cp = configparser.RawConfigParser()
if os.path.exists(creds_path):
    cp.read(creds_path)

sso_profiles = []
all_cfg_profiles = []
for section in cfg.sections():
    if section.startswith("profile "):
        name = section.split("profile ", 1)[1]
        all_cfg_profiles.append(name)
        has_sso_key = any(k.startswith("sso_") for k in cfg.options(section))
        if has_sso_key or not cp.has_section(name):
            sso_profiles.append(name)

if query:
    q = query.lower()
    pool = sso_profiles if sso_profiles else all_cfg_profiles
    exact = [p for p in pool if p.lower() == q]
    if exact:
        print(exact[0])
        sys.exit(0)
    partial = [p for p in pool if q in p.lower()]
    if partial:
        print(partial[0])
        sys.exit(0)
    if sso_profiles:
        sys.stderr.write(
            f"No SSO profile matching '{query}' in {cfg_path}.\n"
            f"Available SSO profiles: {', '.join(sso_profiles)}\n"
        )
        sys.exit(1)
    print(query)
    sys.exit(0)

if default_sso:
    print(default_sso)
    sys.exit(0)

if active_prof and active_prof in sso_profiles:
    print(active_prof)
    sys.exit(0)

if len(sso_profiles) == 1:
    print(sso_profiles[0])
    sys.exit(0)

if len(sso_profiles) > 1:
    sys.stderr.write(
        f"Multiple SSO profiles found in {cfg_path}: {', '.join(sso_profiles)}\n"
        "Specify one with: awsp login sso <profile>\n"
    )
    sys.exit(1)

if active_prof:
    print(active_prof)
    sys.exit(0)

sys.stderr.write(
    f"No SSO profiles found in {cfg_path}. Specify one with: awsp login sso <profile>\n"
)
sys.exit(1)
PY
}

awsp() {
  local creds="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  local cfg="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
  local okta_cfg="${OKTA_AWS_LOGIN_CONFIG:-$HOME/.okta_aws_login_config}"

  if [[ $# -eq 0 || "$1" == "list" || "$1" == "ls" ]]; then
    _awsp_list "$creds" "$cfg" "$okta_cfg"
    return 0
  fi

  if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    cat <<'EOF'
Usage:
  awsp                       List all AWS profiles (with expiry) and Okta login targets
  awsp list | ls             Same as running 'awsp' with no arguments
  awsp <substring>           Switch AWS_PROFILE to matching profile (prefers VALID over EXPIRED)
  awsp login                 Log in via gimme-aws-creds (DEFAULT target) and list profiles
  awsp login <okta-target>   Log in to a specific Okta target in ~/.okta_aws_login_config
  awsp login all             Log in to all Okta targets in ~/.okta_aws_login_config
  awsp login sso [profile]   Run 'aws sso login' for an SSO profile (auto-detected if only one)
  awsp - | clear             Unset AWS_PROFILE
EOF
    return 0
  fi

  if [[ "$1" == "login" ]]; then
    shift
    local target="${1:-DEFAULT}"
    if [[ "$target" == "sso" ]]; then
      local sso_prof
      sso_prof=$(_awsp_resolve_sso_profile "$cfg" "$creds" "${2:-}") || return 1
      echo "Running: aws sso login --profile $sso_prof"
      aws sso login --profile "$sso_prof"
    elif [[ "$target" == "all" ]]; then
      local t
      while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        echo "=== Logging into Okta target: $t ==="
        gimme-aws-creds -p "$t" || true
      done <<EOF
DEFAULT
$(sed -n 's/^[[:space:]]*\[\([^]]*\)\].*/\1/p' "$okta_cfg" 2>/dev/null | grep -v '^DEFAULT$')
EOF
    elif [[ "$target" == "DEFAULT" || "$target" == "default" ]]; then
      echo "Running: gimme-aws-creds (DEFAULT)"
      gimme-aws-creds
    else
      local okta_match
      okta_match=$(sed -n 's/^[[:space:]]*\[\([^]]*\)\].*/\1/p' "$okta_cfg" 2>/dev/null | grep -iF -- "$target" | head -n 1)
      if [[ -z "$okta_match" ]]; then
        echo "No Okta target matching '$target' in $okta_cfg." >&2
        return 1
      fi
      echo "Running: gimme-aws-creds -p $okta_match"
      gimme-aws-creds -p "$okta_match"
    fi
    echo ""
    _awsp_list "$creds" "$cfg" "$okta_cfg"
    return 0
  fi

  if [[ "$1" == "-" || "$1" == "clear" ]]; then
    unset AWS_PROFILE
    echo "Cleared AWS_PROFILE"
    return 0
  fi

  local match_out
  match_out=$(python3 - "$creds" "$cfg" "$1" <<'PY'
import configparser, datetime, os, sys

creds_path, cfg_path, query = sys.argv[1:4]
q = query.lower()
now = datetime.datetime.now(datetime.timezone.utc)

cp = configparser.RawConfigParser()
if os.path.exists(creds_path):
    cp.read(creds_path)

cfg = configparser.RawConfigParser()
if os.path.exists(cfg_path):
    cfg.read(cfg_path)

candidates = []
for idx, section in enumerate(cp.sections()):
    if q in section.lower():
        exp = cp.get(section, "x_security_token_expires", fallback=None)
        valid_rank = 1
        msg = f"AWS_PROFILE={section}"
        if exp:
            try:
                dt = datetime.datetime.fromisoformat(exp)
                rem = int((dt - now).total_seconds() // 60)
                if rem > 0:
                    valid_rank = 0
                    msg = f"AWS_PROFILE={section}  [VALID: {rem}m remaining]"
                else:
                    valid_rank = 2
                    msg = f"AWS_PROFILE={section}  [WARNING: token EXPIRED — run 'awsp login [target]' to refresh]"
            except Exception:
                pass
        exact_rank = 0 if section.lower() == q else 1
        candidates.append((valid_rank, exact_rank, idx, section, msg))

offset = len(cp.sections())
for idx, section in enumerate(cfg.sections()):
    if section.startswith("profile "):
        name = section.split("profile ", 1)[1]
        if not cp.has_section(name) and q in name.lower():
            exact_rank = 0 if name.lower() == q else 1
            msg = f"AWS_PROFILE={name}  (SSO profile — run 'awsp login sso' if expired)"
            candidates.append((1, exact_rank, offset + idx, name, msg))

if not candidates:
    sys.exit(1)

candidates.sort(key=lambda item: (item[0], item[1], item[2]))
best = candidates[0]
print(best[3])
print(best[4])
PY
  ) || {
    echo "No AWS profile matching '$1'. Run 'awsp' to list profiles, or 'awsp login [target]' to fetch credentials." >&2
    return 1
  }

  local match_prof="${match_out%%$'\n'*}"
  local match_msg="${match_out#*$'\n'}"
  export AWS_PROFILE="$match_prof"
  echo "$match_msg"
}

_awsp_complete_candidates() {
  local mode="${1:-root}"
  local creds="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  local cfg="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
  local okta_cfg="${OKTA_AWS_LOGIN_CONFIG:-$HOME/.okta_aws_login_config}"

  if [[ "$mode" == "root" ]]; then
    printf '%s\n' list ls login clear help
    [[ -f "$creds" ]] && sed -n 's/^[[:space:]]*\[\([^]]*\)\].*/\1/p' "$creds" 2>/dev/null
    [[ -f "$cfg" ]] && sed -n 's/^[[:space:]]*\[profile[[:space:]]\{1,\}\([^]]*\)\].*/\1/p' "$cfg" 2>/dev/null
  elif [[ "$mode" == "login" ]]; then
    printf '%s\n' DEFAULT all sso
    [[ -f "$okta_cfg" ]] && sed -n 's/^[[:space:]]*\[\([^]]*\)\].*/\1/p' "$okta_cfg" 2>/dev/null | grep -v '^DEFAULT$'
  elif [[ "$mode" == "sso" ]]; then
    [[ -f "$cfg" ]] && sed -n 's/^[[:space:]]*\[profile[[:space:]]\{1,\}\([^]]*\)\].*/\1/p' "$cfg" 2>/dev/null
  fi
}

if [[ -n "${ZSH_VERSION:-}" ]]; then
  _awsp_zsh_complete() {
    local mode="" line
    local -a candidates
    if [[ ${CURRENT:-0} -eq 2 ]]; then
      mode="root"
    elif [[ ${CURRENT:-0} -eq 3 && "${words[2]:-}" == "login" ]]; then
      mode="login"
    elif [[ ${CURRENT:-0} -eq 4 && "${words[2]:-}" == "login" && "${words[3]:-}" == "sso" ]]; then
      mode="sso"
    else
      return 0
    fi
    while IFS= read -r line; do
      [[ -n "$line" ]] && candidates+=("$line")
    done <<EOF
$(_awsp_complete_candidates "$mode")
EOF
    compadd -Q -- "${candidates[@]}"
  }
  if ! type compdef >/dev/null 2>&1; then
    autoload -Uz compinit && compinit -C 2>/dev/null
  fi
  type compdef >/dev/null 2>&1 && compdef _awsp_zsh_complete awsp
elif [[ -n "${BASH_VERSION:-}" ]]; then
  _awsp_bash_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]:-}"
    local mode="" line
    COMPREPLY=()
    if [[ ${COMP_CWORD:-0} -eq 1 ]]; then
      mode="root"
    elif [[ ${COMP_CWORD:-0} -eq 2 && "${COMP_WORDS[1]:-}" == "login" ]]; then
      mode="login"
    elif [[ ${COMP_CWORD:-0} -eq 3 && "${COMP_WORDS[1]:-}" == "login" && "${COMP_WORDS[2]:-}" == "sso" ]]; then
      mode="sso"
    else
      return 0
    fi
    while IFS= read -r line; do
      if [[ -n "$line" && "$line" == "$cur"* ]]; then
        COMPREPLY+=("$line")
      fi
    done <<EOF
$(_awsp_complete_candidates "$mode")
EOF
  }
  complete -F _awsp_bash_complete awsp
fi
