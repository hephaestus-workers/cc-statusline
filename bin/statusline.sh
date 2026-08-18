#!/bin/bash
# cc-statusline - https://github.com/hephaestus-workers/cc-statusline
# The name above is how the installer recognises its own file, so that an
# upgrade is never mistaken for a statusline worth backing up.
set -f

# Replaced with the package version when the installer copies this file. A copy
# run straight from the repository keeps the placeholder and never self-updates.
installed_version="__CC_STATUSLINE_VERSION__"

# Force a consistent locale so date/printf output looks the same everywhere
# (e.g. "2:00pm" instead of localized AM/PM markers)
export LC_ALL=C

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

# GNU date (Linux / Git Bash on Windows) is tried first, BSD date (macOS) second
format_epoch_time() {
    local epoch=$1
    local style=$2
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -d "@$epoch" +"%l:%M%P" 2>/dev/null)
            [ -z "$result" ] && result=$(date -j -r "$epoch" +"%l:%M%p" 2>/dev/null)
            result=$(echo "$result" | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        datetime)
            result=$(date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null)
            [ -z "$result" ] && result=$(date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null)
            result=$(echo "$result" | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        *)
            result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            [ -z "$result" ] && result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    printf "%s" "$result"
}

iso_to_epoch() {
    local iso_str="$1"

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# ── Extract JSON data ───────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# ── Account (multi-account support) ─────────────────────
# When CLAUDE_CONFIG_DIR is used to keep one config directory per account,
# .claude.json lives inside it; otherwise it is $HOME/.claude.json
account_config_dir="${CLAUDE_CONFIG_DIR:-$HOME}"
account_file="$account_config_dir/.claude.json"
account_label=""
if [ -f "$account_file" ]; then
    account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$account_file" 2>/dev/null)
    if [ -n "$account_email" ]; then
        # Show only the local part (before @). Use account_label="$account_email"
        # instead if you prefer the full address.
        account_label="${account_email%%@*}"
    fi
fi

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

effort="default"
settings_path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$settings_path" ]; then
    effort=$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)
fi

# ── LINE 1: Model │ Account │ Context % │ Directory (branch) │ Session │ Effort ──
pct_color=$(color_for_pct "$pct_used")
cwd=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
# Windows paths may use backslashes; normalize so basename works
dirname=$(basename "${cwd//\\//}")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
fi

session_duration=""
session_start=$(echo "$input" | jq -r '.session.start_time // empty')
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    if [ -n "$start_epoch" ]; then
        now_epoch=$(date +%s)
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

skip_perms=""
parent_cmd=$(ps -o args= -p "$PPID" 2>/dev/null)
if [[ "$parent_cmd" == *"--dangerously-skip-permissions"* ]]; then
    skip_perms="⚡  "
fi

line1="${blue}${model_name}${reset}"
if [ -n "$account_label" ]; then
    line1+="${sep}"
    line1+="${yellow}👤 ${account_label}${reset}"
fi
line1+="${sep}"
line1+="✍️ ${pct_color}${pct_used}%${reset}"
line1+="${sep}"
line1+="${skip_perms}${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
fi
if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi
line1+="${sep}"
case "$effort" in
    high)   line1+="${magenta}● ${effort}${reset}" ;;
    medium) line1+="${dim}◑ ${effort}${reset}" ;;
    low)    line1+="${dim}◔ ${effort}${reset}" ;;
    *)      line1+="${dim}◑ ${effort}${reset}" ;;
esac

# ── Rate limits from stdin (primary) ───────────────────
has_stdin_rates=false
five_hour_pct=""
five_hour_reset_epoch=""
seven_day_pct=""
seven_day_reset_epoch=""

stdin_five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$stdin_five_pct" ]; then
    has_stdin_rates=true
    five_hour_pct=$(printf "%.0f" "$stdin_five_pct")
    five_hour_reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | awk '{printf "%.0f", $1}')
    seven_day_reset_epoch=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
fi

# ── Usage API snapshot (cached) ────────────────────────
# The status line stdin JSON only carries five_hour / seven_day. Model-scoped
# weekly limits (Fable etc.) and extra usage exist only in the OAuth usage
# API, so the snapshot is kept fresh even when stdin already has rate limits.
# Per-user cache dir (not the shared /tmp), and one cache file per config
# dir so multiple accounts don't overwrite each other's usage data
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cc-statusline"
cache_key=$(printf '%s' "$account_config_dir" | cksum 2>/dev/null | cut -d' ' -f1)
[ -z "$cache_key" ] && cache_key="default"
cache_file="$cache_dir/usage-cache-${cache_key}.json"
fail_file="$cache_dir/usage-fail-${cache_key}"
lock_dir="$cache_dir/usage-lock-${cache_key}"
cache_max_age=60    # refresh the snapshot at most once a minute
fail_max_age=300    # back off this long after a failed fetch
lock_max_age=30     # a lock older than this is treated as abandoned
mkdir -p "$cache_dir" 2>/dev/null

now_ts=$(date +%s)

# Sets $_file_age rather than echoing it, to save a subshell per call
file_age() {
    local mtime
    _file_age=""
    mtime=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
    [ -z "$mtime" ] && return 1
    _file_age=$(( now_ts - mtime ))
    return 0
}

read_oauth_token() {
    local token="" blob="" creds_file
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi
    if command -v security >/dev/null 2>&1; then
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        [ -n "$blob" ] && token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        creds_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
        [ -f "$creds_file" ] && token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
    fi
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        if command -v secret-tool >/dev/null 2>&1; then
            blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
            [ -n "$blob" ] && token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        fi
    fi
    [ "$token" = "null" ] && token=""
    printf '%s' "$token"
}

refresh_usage_cache() {
    local token response
    token=$(read_oauth_token)
    [ -z "$token" ] && { : > "$fail_file" 2>/dev/null; return 1; }
    # The Authorization header is fed via stdin (-H @-) so the token
    # never appears in the process list (upstream issue #29)
    response=$(printf 'Authorization: Bearer %s\n' "$token" | curl -s --max-time 5 \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H @- \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/2.1.34" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
        printf '%s' "$response" > "$cache_file"
        rm -f "$fail_file" 2>/dev/null
        return 0
    fi
    : > "$fail_file" 2>/dev/null
    return 1
}

usage_data=""
extra_enabled="false"

cache_age=""
if [ -f "$cache_file" ]; then
    usage_data=$(cat "$cache_file" 2>/dev/null)
    file_age "$cache_file" && cache_age=$_file_age
fi

needs_refresh=true
[ -n "$cache_age" ] && [ "$cache_age" -lt "$cache_max_age" ] && needs_refresh=false
if $needs_refresh && [ -f "$fail_file" ]; then
    file_age "$fail_file" && [ "$_file_age" -lt "$fail_max_age" ] && needs_refresh=false
fi

if $needs_refresh; then
    # A status line run that Claude Code cancelled mid-fetch can leave the
    # lock behind, so drop it once it is clearly too old to be live
    if [ -d "$lock_dir" ]; then
        file_age "$lock_dir" && [ "$_file_age" -ge "$lock_max_age" ] && rmdir "$lock_dir" 2>/dev/null
    fi
    if mkdir "$lock_dir" 2>/dev/null; then
        if [ -z "$usage_data" ]; then
            # Nothing cached yet: fetch inline so the first render has data
            refresh_usage_cache && usage_data=$(cat "$cache_file" 2>/dev/null)
            rmdir "$lock_dir" 2>/dev/null
        else
            # Refresh in the background and render the cached snapshot now.
            # Claude Code cancels a status line script that is still running
            # when the next update fires, so a blocking fetch would often
            # never finish. stdio is detached so this run can exit at once.
            ( trap '' HUP; refresh_usage_cache; rmdir "$lock_dir" 2>/dev/null ) \
                </dev/null >/dev/null 2>&1 &
        fi
    fi
fi


# ── Self-update check (background, about once a day) ────
# Claude Code runs ~/.claude/statusline.sh, a copy taken at install time, so a
# new release never reaches an existing install on its own. Ask the npm
# registry roughly once a day and let the installer swap this file out. The
# installer renames the new file into place, so a run already in flight keeps
# reading the copy it started with. Set CC_STATUSLINE_NO_SELF_UPDATE=1 to
# turn this off.
update_stamp="$cache_dir/last-update-check"
update_lock="$cache_dir/update-lock"
update_interval=86400   # once a day is plenty for a status line
update_lock_max_age=900 # npx can be slow; only assume abandonment after this

# An unstamped copy (running from a checkout) or a botched substitution must
# never trigger an update, so require something that looks like a version
case "$installed_version" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) installed_version="" ;;
esac

# True when $1 is a higher version than $2. Compares each dotted field as a
# number so 1.10.0 beats 1.9.0, and only ever moves forward: an install that
# is somehow ahead of the registry is left alone rather than downgraded.
version_gt() {
    local a="$1" b="$2" ai bi
    [ "$a" = "$b" ] && return 1
    while [ -n "$a" ] || [ -n "$b" ]; do
        ai=${a%%.*}; bi=${b%%.*}
        ai=${ai%%[!0-9]*}; bi=${bi%%[!0-9]*}
        [ -z "$ai" ] && ai=0
        [ -z "$bi" ] && bi=0
        [ "$ai" -gt "$bi" ] 2>/dev/null && return 0
        [ "$ai" -lt "$bi" ] 2>/dev/null && return 1
        case "$a" in *.*) a=${a#*.} ;; *) a="" ;; esac
        case "$b" in *.*) b=${b#*.} ;; *) b="" ;; esac
    done
    return 1
}

if [ -n "$installed_version" ] && [ "$CC_STATUSLINE_NO_SELF_UPDATE" != "1" ] \
   && command -v npx >/dev/null 2>&1; then
    update_due=true
    if [ -f "$update_stamp" ]; then
        file_age "$update_stamp" && [ "$_file_age" -lt "$update_interval" ] && update_due=false
    fi
    if $update_due; then
        if [ -d "$update_lock" ]; then
            file_age "$update_lock" && [ "$_file_age" -ge "$update_lock_max_age" ] && rmdir "$update_lock" 2>/dev/null
        fi
        if mkdir "$update_lock" 2>/dev/null; then
            (
                trap '' HUP
                # Stamp first: a failed check should still wait a day, not
                # retry on every render
                : > "$update_stamp"
                latest=$(curl -s --max-time 10 \
                    "https://registry.npmjs.org/@hephaestus-workers%2Fcc-statusline/latest" \
                    2>/dev/null | jq -r '.version // empty' 2>/dev/null)
                latest=${latest//$'\r'/}
                if [ -n "$latest" ] && version_gt "$latest" "$installed_version"; then
                    # npx resolves against the current directory's package.json,
                    # and inside a checkout of this project that makes it skip
                    # the download entirely, so run it somewhere neutral
                    cd "$HOME" 2>/dev/null || cd / 2>/dev/null
                    if command -v timeout >/dev/null 2>&1; then
                        timeout 300 npx -y "@hephaestus-workers/cc-statusline@$latest"
                    else
                        npx -y "@hephaestus-workers/cc-statusline@$latest"
                    fi
                fi
                rmdir "$update_lock" 2>/dev/null
            ) </dev/null >/dev/null 2>&1 &
        fi
    fi
fi
# One jq pass over the snapshot, emitting tab-separated records:
#   extra   <is_enabled>
#   window  five|seven      <percent>  <resets_at>
#   scoped  <padded label>  <percent>  <resets_at>
# No output at all means the snapshot is missing or unusable.
#
# Model-scoped weekly limits (Fable etc.) never appear on stdin. The usage API
# reports them as limits[] entries with kind="weekly_scoped" and a
# scope.model.display_name; older shapes of the same response used
# seven_day_opus / seven_day_sonnet. The label comes from whatever the API
# reports, so a renamed or additional scoped model needs no code change.
usage_summary=""
if [ -n "$usage_data" ]; then
    usage_summary=$(printf '%s' "$usage_data" | jq -r '
        def as_pct: (. // 0) | round | tostring;
        def scoped_limits:
            ([ (.limits // [])[]
               | select(.kind == "weekly_scoped")
               | select((.scope.model.display_name // "") != "")
               | { name: .scope.model.display_name,
                   pct: (.percent // 0),
                   reset: (.resets_at // "") } ]) as $scoped
            | if ($scoped | length) > 0 then $scoped
              else
                [ { name: "opus",   w: .seven_day_opus },
                  { name: "sonnet", w: .seven_day_sonnet } ]
                | map(select(.w != null)
                      | { name: .name,
                          pct: (.w.utilization // 0),
                          reset: (.w.resets_at // "") })
              end;
        [ "extra",  ((.extra_usage.is_enabled // false) | tostring) ],
        [ "window", "five",  (.five_hour.utilization  | as_pct), (.five_hour.resets_at  // "") ],
        [ "window", "seven", (.seven_day.utilization  | as_pct), (.seven_day.resets_at // "") ],
        ( scoped_limits[]
          | [ "scoped",
              (((.name | ascii_downcase) + "       ")[0:7]),
              (.pct | as_pct),
              .reset ] )
        | @tsv
    ' 2>/dev/null)
    # The Windows build of jq terminates lines with CRLF
    usage_summary=${usage_summary//$'\r'/}
fi

api_five_pct=""
api_five_reset=""
api_seven_pct=""
api_seven_reset=""
scoped_labels=()
scoped_pcts=()
scoped_resets=()

if [ -z "$usage_summary" ]; then
    usage_data=""
else
    while IFS=$'\t' read -r rec_kind rec_a rec_b rec_c; do
        case "$rec_kind" in
            extra)
                extra_enabled="$rec_a"
                ;;
            window)
                if [ "$rec_a" = "five" ]; then
                    api_five_pct="$rec_b"
                    api_five_reset="$rec_c"
                else
                    api_seven_pct="$rec_b"
                    api_seven_reset="$rec_c"
                fi
                ;;
            scoped)
                scoped_labels+=("$rec_a")
                scoped_pcts+=("$rec_b")
                scoped_resets+=("$rec_c")
                ;;
        esac
    done <<< "$usage_summary"
fi

# stdin is authoritative when present; the API snapshot is the fallback
if ! $has_stdin_rates && [ -n "$usage_data" ]; then
    five_hour_pct="$api_five_pct"
    seven_day_pct="$api_seven_pct"
    [ -n "$api_five_reset" ]  && five_hour_reset_epoch=$(iso_to_epoch "$api_five_reset")
    [ -n "$api_seven_reset" ] && seven_day_reset_epoch=$(iso_to_epoch "$api_seven_reset")
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_hour_pct" ]; then
    five_hour_reset=$(format_epoch_time "$five_hour_reset_epoch" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    five_hour_pct_color=$(color_for_pct "$five_hour_pct")
    five_hour_pct_fmt=$(printf "%3d" "$five_hour_pct")

    rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct_fmt}%${reset}"
    [ -n "$five_hour_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"
fi

if [ -n "$seven_day_pct" ]; then
    seven_day_reset=$(format_epoch_time "$seven_day_reset_epoch" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    seven_day_pct_color=$(color_for_pct "$seven_day_pct")
    seven_day_pct_fmt=$(printf "%3d" "$seven_day_pct")

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}weekly${reset}  ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct_fmt}%${reset}"
    [ -n "$seven_day_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"
fi

# ── Model-scoped weekly limits (Fable etc.) ─────────────
# Labels arrive from jq already lowercased and padded to the width of
# "current", so every bar starts in the same column
for scoped_i in "${!scoped_labels[@]}"; do
    scoped_pct="${scoped_pcts[$scoped_i]}"
    [ -z "$scoped_pct" ] && continue

    scoped_bar=$(build_bar "$scoped_pct" "$bar_width")
    scoped_pct_color=$(color_for_pct "$scoped_pct")
    printf -v scoped_pct_fmt "%3d" "$scoped_pct"

    scoped_reset=""
    if [ -n "${scoped_resets[$scoped_i]}" ]; then
        scoped_reset=$(format_epoch_time "$(iso_to_epoch "${scoped_resets[$scoped_i]}")" "datetime")
    fi

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}${scoped_labels[$scoped_i]}${reset} ${scoped_bar} ${scoped_pct_color}${scoped_pct_fmt}%${reset}"
    [ -n "$scoped_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${scoped_reset}${reset}"
done

if [ "$extra_enabled" = "true" ] && [ -n "$usage_data" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")
    extra_pct_color=$(color_for_pct "$extra_pct")

    extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ -z "$extra_reset" ]; then
        extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0
