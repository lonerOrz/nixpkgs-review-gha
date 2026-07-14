#!/usr/bin/env nu
# Test harness for build-pr/*.nu
# Run from repo root:  nu build-pr/test.nu
# Requires: nu on PATH. Exercises script logic with mocked env; does NOT run nix/gh/telegram for real.

def assert [cond: bool, msg: string] {
  if $cond {
    print $"  ok   ($msg)"
  } else {
    error make { msg: $"  FAIL ($msg)" }
  }
}

let repo = (pwd)
let nu_bin = ($env.NU_BIN? | default "nu")
let scripts = [gha.nu check-creds.nu prepare.nu build.nu report.nu post-result.nu]
let work = ($env.XDG_RUNTIME_DIR? | default "/tmp") + "/build-pr-test"
rm -rf $work
mkdir $work
cd $work

print "=== 1. syntax check ==="
for s in $scripts {
  let path = $"($repo)/build-pr/($s)"
  let out = (^($nu_bin) --no-config-file -c $"source ($path)" | complete | get stderr | str join "\n")
  if ($out | str contains "nu::parser") {
    error make { msg: $"  PARSE FAIL ($s)\n($out)" }
  }
  print $"  ok   ($s) parses"
}

print "=== 2. check-creds ==="
let creds_out = $"($work)/creds_out"
"" | save -f $creds_out
with-env {
  GH_TOKEN_SECRET: "x", CACHIX_AUTH_TOKEN: "c", TG_BOT_TOKEN: "t", TG_CHAT_ID: "1",
  GITHUB_OUTPUT: $creds_out,
} {
  ^($nu_bin) --no-config-file $"($repo)/build-pr/check-creds.nu"
}
let creds = (open $creds_out)
assert ($creds | str contains "gh_token=true") "gh_token=true emitted"
assert ($creds | str contains "cachix=true") "cachix=true emitted"
assert ($creds | str contains "tg=true") "tg=true emitted"

print "=== 3. prepare ==="
let prep_out = $"($work)/prep_out"
"" | save -f $prep_out
with-env {
  INPUTS: ({
    "pr-number": "5",
    packages: "firefox, chromium; vim",
    system: "github:default-linux github:default-darwin",
    cachix_name: "mycache", report_to_api: "false", telegram_enabled: "true",
    telegram_bot_token: "X", telegram_chat_id: "Y", cachix_enabled: "true",
    cachix_auth_token: "Z", pr_title: "t", pr_body: "b", pr_author: "u",
    pr_head_label: "u:br", pr_base_label: "N:master", pr_changed_files: "2",
    is_pr: "true", ref_name: "br",
  } | to json -r),
  GITHUB_OUTPUT: $prep_out,
} {
  ^($nu_bin) --no-config-file $"($repo)/build-pr/prepare.nu"
}
let pkgs = (open $prep_out | lines | where ($it | str starts-with "packages=") | first | str substring 9.. | from json)
assert ($pkgs == ["firefox" "chromium" "vim"]) $"packages parsed: ($pkgs)"

print "=== 4. report (with fake build artifacts) ==="
# Simulate what build.nu would have uploaded
{
  md: "x", successful: true, system: "github:default-linux", package: "firefox",
  job_url: "https://github.com/o/r/actions/runs/1",
} | to json | save -f $"($work)/build_report_github:default-linux_firefox.json"
{
  md: "x", successful: false, system: "github:default-darwin", package: "chromium",
  job_url: "https://github.com/o/r/actions/runs/1",
} | to json | save -f $"($work)/build_report_github:default-darwin_chromium.json"

let summary = $"($work)/summary.md"
"" | save -f $summary
with-env {
  INPUTS: ({
    "pr-number": "5", packages: "firefox chromium", system: "github:default-linux github:default-darwin",
    cachix_name: "mycache", report_to_api: "false", pr_title: "t", pr_body: "b", pr_author: "u",
    pr_head_label: "u:br", pr_base_label: "N:master", pr_changed_files: "2", is_pr: "true", ref_name: "br",
  } | to json -r),
  TG_ENABLED: "true",
  GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "1", GITHUB_SERVER_URL: "https://github.com",
  GITHUB_OUTPUT: $"($work)/report_out", GITHUB_STEP_SUMMARY: $summary,
} {
  ^($nu_bin) --no-config-file $"($repo)/build-pr/report.nu"
}
assert (ls $"($work)/report.md" | is-not-empty) "report.md generated"
let report_md = (open --raw $"($work)/report.md")
assert ($report_md | str contains "firefox") "report.md lists firefox"
assert ($report_md | str contains "chromium") "report.md lists chromium"
assert ($report_md | str contains "Success") "report.md shows success row"
assert ($report_md | str contains "Failed") "report.md shows failed row"
let sum = (open --raw $summary)
assert ($sum | str contains "#5") "step-summary links PR #5"
let tg = (open $"($work)/telegram-notification.txt")
assert ($tg | str contains "o/r#5") "telegram message references o/r#5"
assert ($tg | str contains "builds passed") "telegram message has pass count"
assert ($tg | str contains "chromium") "telegram lists failed chromium build"

print "=== 5. post-result early-exit gate ==="
with-env {
  INPUTS: ({ "pr-number": "5" } | to json -r),
  GITHUB_REPOSITORY: "o/r", GITHUB_TOKEN: "x", GH_TOKEN_ENABLED: "false", BUILD_SUCCESS: "true",
} {
  # when GH_TOKEN_ENABLED != 'true' it must exit before any gh call (gh not installed here)
  ^($nu_bin) --no-config-file $"($repo)/build-pr/post-result.nu"
}
assert true "post-result exits cleanly when GH_TOKEN disabled"

print ""
print "ALL TESTS PASSED"
