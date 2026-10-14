# deploy_agent_agisa1-u

`deploy_agent.sh` bootstraps, runs and archives logs for the **Student Attendance Tracker** (`attendance_checker.py`), and handles Ctrl+C / Ctrl+Z cleanly while deploying. The Python app is never modified.

## Repository layout

```
deploy_agent_agisa1-u/
├── deploy_agent.sh              # master script (3 features + signal handling)
├── README.md
└── templates/                   # unmodified source files
    ├── attendance_checker.py
    ├── config.json
    └── assets.csv
```

A deployed project looks like this:

```
attendance_tracker_{input}/
├── attendance_checker.py
├── Helpers/
│   ├── assets.csv
│   └── config.json
├── reports/                     # app creates attendance.log / absent.log here
└── archives/                    # created by Feature 3
    ├── attendance/
    └── absent/
```

## How to run and select a feature

Requirements: `bash`, `python3`, `zip`.

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh                # interactive menu (1 Deploy, 2 Run, 3 Archive, 4 Quit)
./deploy_agent.sh --deploy       # Feature 1
./deploy_agent.sh --run          # Feature 2
./deploy_agent.sh --archive      # Feature 3
./deploy_agent.sh --help
```

Both the menu and the flags are available. Both end up in the same functions.

## Feature 1: Deploy

1. **Pre-flight**: checks `python3` and `zip`; exits with a clear message if either is missing.
2. **Project name**: asks for a name (letters, digits, `-`, `_` only) and creates `attendance_tracker_{input}/`. If it already exists you are asked whether to overwrite; answering no aborts with an error and touches nothing.
3. **Populate**: `attendance_checker.py` and `config.json` are copied from `templates/`. The roster is built by your choice:
   - **Option A**: copy N students (plus header) from `templates/assets.csv`.
   - **Option B**: generate N students from sample name/email arrays in the script, with counts at 0.
4. **Permissions**: `chmod +x attendance_checker.py`, `chmod 600 Helpers/config.json`, then prints the resulting `ls -l` lines.
5. **Thresholds** (optional): see below.
6. **Verify**: finishes by running the app (Feature 2). A successful startup proves structure, roster and config work together.

### `total_sessions` and the roster

`total_sessions` must be **one more than the prior sessions in the roster**.
- Option A rows each carry 4 prior sessions, so `total_sessions` stays **5**.
- Option B starts everyone at 0, so this is session one and the script sets `total_sessions` to **1** (the only edit made to `config.json` besides thresholds).

### How the threshold update works

The script asks "Update the attendance alert thresholds? [y/N]". If yes, it reads new `warning` (default 75) and `failure` (default 50) values with `read`, checks they are 0-100 and that failure < warning, then edits the deployed file in place with `sed`, matching only the `"warning": <number>` and `"failure": <number>` lines:

```bash
sed -i.bak -E -e 's/("warning":[[:space:]]*)[0-9]+/\1NEW/' \
               -e 's/("failure":[[:space:]]*)[0-9]+/\1NEW/' Helpers/config.json
```

The file is not reformatted or reordered. (`-i.bak` then deleting the backup keeps it working on both GNU and macOS sed.)

## Feature 2: Run

Asks for the project name and runs `cd attendance_tracker_{input} && python3 attendance_checker.py`. The terminal is handed to the app, which asks Present/Absent for each student and updates `Helpers/assets.csv` and `reports/`.

## Feature 3: Archive logs

Asks for the project name, then for each of `reports/attendance.log` and `reports/absent.log`:
- if it exists, it is **moved** to `archives/attendance/attendance_YYYYMMDD_HHMMSS.log` or `archives/absent/absent_YYYYMMDD_HHMMSS.log` (one timestamp per archive run, so every copy is unique and traceable);
- if it does not exist (e.g. nobody was absent), the script reports that and carries on without crashing.

It prints the final path of every archived file. Because the app appends to its logs, moving them means each archive holds only the sessions since the last archive.

## Signal handling (Ctrl+C / Ctrl+Z)

From the moment the project directory is created until deployment finishes, `SIGINT` and `SIGTSTP` are trapped. On either signal the script:
1. prints that deployment was interrupted,
2. runs `zip -r attendance_tracker_{input}_archive.zip attendance_tracker_{input}` on whatever exists so far,
3. removes the half-made directory and exits (code 130).

The trap is removed before the verification run, so it never affects `attendance_checker.py`. If the user declines to overwrite an existing project, the trap is not yet active, so the existing project is never zipped or deleted. Closed input (EOF) is handled the same way.

### How to test it

```bash
./deploy_agent.sh --deploy
# enter a name, e.g. demo, wait at the "Choose A or B:" prompt, then press Ctrl+C (or Ctrl+Z)
ls                                    # attendance_tracker_demo_archive.zip exists, the directory is gone
unzip -l attendance_tracker_demo_archive.zip
```

The zip contains the partial project at the moment of interruption, e.g. `attendance_checker.py`, `Helpers/config.json` and an empty `reports/`, but no `assets.csv` if you interrupted before choosing a roster.

## How the deployed structure was tested
Link to YouTube ( https://youtu.be/crIVaeG2uzw)
- Deployed with Option A (3 students) and Option B (4 students); confirmed `Helpers/assets.csv` rows, `total_sessions` (5 and 1), and that the app starts and writes `reports/*.log`.
- Confirmed `ls -l` shows `-rwxr-xr-x` for the script and `-rw-------` for `config.json`.
- Changed thresholds to 80/60 and confirmed only those two lines changed and the app used the new values.
- Ran Archive with both logs present, and with no `absent.log`.
- Answered "no" to the overwrite prompt and confirmed the existing project was untouched.
- Sent SIGINT and SIGTSTP mid-deploy and inspected the zip; also tested closed input.
- Hid `python3`/`zip` from `PATH` to confirm the pre-flight message.
