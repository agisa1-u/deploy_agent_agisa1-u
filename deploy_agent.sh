#!/usr/bin/env bash
# =============================================================================
# deploy_agent.sh - Bootstrap, run and archive the Student Attendance Tracker
#
# Usage:
#   ./deploy_agent.sh               interactive menu
#   ./deploy_agent.sh --deploy      Feature 1: deploy the application
#   ./deploy_agent.sh --run         Feature 2: run a deployed application
#   ./deploy_agent.sh --archive     Feature 3: archive the generated logs
#   ./deploy_agent.sh --help
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
cd "$SCRIPT_DIR" || exit 1

# Set ONLY once we are actually creating a directory, so the interrupt handler
# never zips/deletes a pre-existing project the user chose not to overwrite.
CLEANUP_DIR=""

# Sample data for Option B (fresh roster)
SAMPLE_NAMES=("Amara Okafor" "Bruno Silva" "Chen Wei" "Deborah Mutesi" "Elias Tesfaye"
              "Fiona Murphy" "Gaspard Niyonzima" "Hana Sato" "Ivan Petrov" "Joyce Uwase"
              "Kwame Boateng" "Layla Hassan" "Mateo Garcia" "Nadia Karim" "Omar Diallo"
              "Priya Sharma" "Quentin Dubois" "Rita Ncube" "Samuel Kagame" "Tara Nguyen")
SAMPLE_EMAILS=("amara@example.com" "bruno@example.com" "chen@example.com" "deborah@example.com"
               "elias@example.com" "fiona@example.com" "gaspard@example.com" "hana@example.com"
               "ivan@example.com" "joyce@example.com" "kwame@example.com" "layla@example.com"
               "mateo@example.com" "nadia@example.com" "omar@example.com" "priya@example.com"
               "quentin@example.com" "rita@example.com" "samuel@example.com" "tara@example.com")

# ---------- helpers ----------------------------------------------------------
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }

# Read one line into variable $1 with prompt $2. If input is closed (EOF),
# treat it like an interruption so a half-made project is archived and cleaned up.
ask() {
    read -r -p "$2" "$1" || { echo; echo "Input closed."; handle_interrupt; }
}

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

preflight() {
    local missing=0
    for tool in python3 zip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: required tool '$tool' is not installed." >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || die "Pre-flight check failed. Install the missing tool(s) and retry."
    ok "Pre-flight check passed (python3 and zip found)."
}

ask_project_name() {
    local input
    while true; do
        ask input "Enter project name (creates attendance_tracker_<name>): "
        if [[ "$input" =~ ^[A-Za-z0-9_-]+$ ]]; then
            PROJECT_NAME="$input"
            PROJECT_DIR="attendance_tracker_${PROJECT_NAME}"
            return
        fi
        echo "Use only letters, digits, '-' and '_' (no spaces or slashes)."
    done
}

# ---------- signal handling (Ctrl+C / Ctrl+Z during deployment) --------------
handle_interrupt() {
    trap '' SIGINT SIGTSTP          # ignore further signals while cleaning up
    echo
    echo "!! Deployment interrupted (signal received)."
    if [ -n "$CLEANUP_DIR" ] && [ -d "$CLEANUP_DIR" ]; then
        local zipfile="${CLEANUP_DIR}_archive.zip"
        echo "!! Archiving incomplete project to $zipfile ..."
        rm -f "$zipfile"
        if zip -r -q "$zipfile" "$CLEANUP_DIR"; then
            ok "Archive created: $zipfile"
            rm -rf "$CLEANUP_DIR"
            ok "Removed incomplete directory $CLEANUP_DIR."
        else
            echo "ERROR: zip failed; leaving $CLEANUP_DIR in place." >&2
        fi
    else
        echo "!! Nothing had been created yet, so there is nothing to archive."
    fi
    echo "Session closed cleanly."
    exit 130
}

# ---------- Feature 1: deploy ------------------------------------------------
build_roster_template() {
    local max n
    max=$(( $(wc -l < "$TEMPLATES_DIR/assets.csv") - 1 ))
    while true; do
        ask n "How many students to copy from the template (1-$max)? "
        if is_uint "$n" && [ "$n" -ge 1 ] && [ "$n" -le "$max" ]; then break; fi
        echo "Enter a whole number between 1 and $max."
    done
    head -n $((n + 1)) "$TEMPLATES_DIR/assets.csv" > "$PROJECT_DIR/Helpers/assets.csv"
    ok "Copied header + $n student(s) from templates/assets.csv (4 prior sessions each, total_sessions stays 5)."
}

build_roster_fresh() {
    local max=${#SAMPLE_NAMES[@]} n i
    while true; do
        ask n "How many students in the new roster (1-$max)? "
        if is_uint "$n" && [ "$n" -ge 1 ] && [ "$n" -le "$max" ]; then break; fi
        echo "Enter a whole number between 1 and $max."
    done
    {
        echo "Email,Names,Attendance Count,Absence Count"
        for ((i = 0; i < n; i++)); do
            echo "${SAMPLE_EMAILS[$i]},${SAMPLE_NAMES[$i]},0,0"
        done
    } > "$PROJECT_DIR/Helpers/assets.csv"
    # Fresh roster = first session ever, so total_sessions must be 1.
    sed -i.bak -E 's/("total_sessions":[[:space:]]*)[0-9]+/\11/' "$PROJECT_DIR/Helpers/config.json"
    rm -f "$PROJECT_DIR/Helpers/config.json.bak"
    ok "Generated $n student(s) with counts at 0; total_sessions set to 1."
}

read_percent() {   # $1 = label, $2 = default ; sets REPLY_VALUE
    local v
    while true; do
        ask v "New $1 threshold [$2]: "
        v="${v:-$2}"
        if is_uint "$v" && [ "$v" -le 100 ]; then REPLY_VALUE="$v"; return; fi
        echo "Enter a whole number between 0 and 100."
    done
}

update_thresholds() {
    local ans warn fail cfg="$PROJECT_DIR/Helpers/config.json"
    ask ans "Update the attendance alert thresholds? [y/N]: "
    [[ "$ans" =~ ^[Yy] ]] || { info "Keeping default thresholds (warning 75, failure 50)."; return; }
    while true; do
        read_percent "warning" 75; warn="$REPLY_VALUE"
        read_percent "failure" 50; fail="$REPLY_VALUE"
        [ "$fail" -lt "$warn" ] && break
        echo "Failure threshold must be lower than the warning threshold. Try again."
    done
    # Edit only the two target lines, in place, without reformatting the file.
    sed -i.bak -E \
        -e 's/("warning":[[:space:]]*)[0-9]+/\1'"$warn"'/' \
        -e 's/("failure":[[:space:]]*)[0-9]+/\1'"$fail"'/' "$cfg"
    rm -f "$cfg.bak"
    ok "Thresholds updated: warning=$warn, failure=$fail"
}

deploy() {
    preflight
    [ -d "$TEMPLATES_DIR" ] || die "templates/ folder not found next to the script."
    for f in attendance_checker.py config.json assets.csv; do
        [ -f "$TEMPLATES_DIR/$f" ] || die "Missing template: templates/$f"
    done

    ask_project_name
    if [ -d "$PROJECT_DIR" ]; then
        local ow
        ask ow "'$PROJECT_DIR' already exists. Overwrite it? [y/N]: "
        if [[ "$ow" =~ ^[Yy] ]]; then
            rm -rf "$PROJECT_DIR"
        else
            die "Aborted: '$PROJECT_DIR' already exists and was not overwritten."
        fi
    fi

    # From here on, Ctrl+C / Ctrl+Z archive whatever exists so far.
    CLEANUP_DIR="$PROJECT_DIR"
    trap handle_interrupt SIGINT SIGTSTP

    mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" || die "Could not create directories."
    cp "$TEMPLATES_DIR/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py"
    cp "$TEMPLATES_DIR/config.json"           "$PROJECT_DIR/Helpers/config.json"
    ok "Created $PROJECT_DIR/ with Helpers/ and reports/."

    echo "Roster options:"
    echo "  A) Copy rows from templates/assets.csv"
    echo "  B) Generate a fresh roster (all counts start at 0)"
    local choice
    while true; do
        ask choice "Choose A or B: "
        case "${choice,,}" in
            a) build_roster_template; break ;;
            b) build_roster_fresh;    break ;;
            *) echo "Please enter A or B." ;;
        esac
    done

    chmod +x "$PROJECT_DIR/attendance_checker.py"
    chmod 600 "$PROJECT_DIR/Helpers/config.json"
    ok "Permissions set:"
    ls -l "$PROJECT_DIR/attendance_checker.py" "$PROJECT_DIR/Helpers/config.json" | awk '{print "    " $1 "  " $NF}'

    update_thresholds

    # Deployment finished: stop trapping so Ctrl+C inside the app is the app's own business.
    trap - SIGINT SIGTSTP
    CLEANUP_DIR=""
    ok "Deployment complete. Verifying by launching the application..."
    run_app "$PROJECT_DIR"
}

# ---------- Feature 2: run ---------------------------------------------------
run_app() {
    local dir="$1"
    [ -d "$dir" ] || die "Project '$dir' not found. Deploy it first."
    command -v python3 >/dev/null 2>&1 || die "python3 is not installed."
    ( cd "$dir" && python3 attendance_checker.py )
}

run_feature() {
    ask_project_name
    run_app "$PROJECT_DIR"
}

# ---------- Feature 3: archive -----------------------------------------------
archive_logs() {
    ask_project_name
    [ -d "$PROJECT_DIR" ] || die "Project '$PROJECT_DIR' not found."
    local ts archived=0 skipped=()
    ts="$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$PROJECT_DIR/archives/attendance" "$PROJECT_DIR/archives/absent"

    local name src dest
    for name in attendance absent; do
        src="$PROJECT_DIR/reports/${name}.log"
        dest="$PROJECT_DIR/archives/${name}/${name}_${ts}.log"
        if [ -f "$src" ]; then
            mv "$src" "$dest" && { ok "Archived ${name}.log -> $dest"; archived=$((archived + 1)); }
        else
            skipped+=("${name}.log")
        fi
    done

    for s in "${skipped[@]}"; do
        info "reports/$s does not exist (nothing to archive)."
    done
    [ "$archived" -gt 0 ] || info "No logs were archived. Run the application first."
}

# ---------- menu / entry point -----------------------------------------------
usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

menu() {
    echo "=============================="
    echo "  Attendance Tracker Deployer"
    echo "=============================="
    echo "  1) Deploy the application"
    echo "  2) Run the application"
    echo "  3) Archive the log files"
    echo "  4) Quit"
    local c
    ask c "Select an option [1-4]: "
    case "$c" in
        1) deploy ;;
        2) run_feature ;;
        3) archive_logs ;;
        4) exit 0 ;;
        *) die "Invalid option '$c'." ;;
    esac
}

case "${1:-}" in
    "")          menu ;;
    --deploy)    deploy ;;
    --run)       run_feature ;;
    --archive)   archive_logs ;;
    -h|--help)   usage ;;
    *)           usage; exit 1 ;;
esac
