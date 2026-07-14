use gha.nu *

let system = $env.MATRIX_SYSTEM
let package = $env.MATRIX_PACKAGE

if $env.RUNNER_OS == 'Linux' {
  gha group "machine specs" {
    print "===== MACHINE ====="
    print $"Runner: ($env.RUNNER_NAME)"
    print $"OS: ($env.RUNNER_OS)"
    print $"Arch: ($env.RUNNER_ARCH)"
    print $"Image: (($env.ImageOS? | default 'unknown')) (($env.ImageVersion? | default 'unknown'))"
    print ""
    print "===== CPU ====="
    ^nproc
    ^lscpu | lines | where {|l| ['Model name' 'CPU(s)' 'Thread' 'Core' 'Socket'] | any {|p| $l | str contains $p } }
    print ""
    print "===== MEMORY ====="
    ^free -h
    print ""
    print "===== SWAP ====="
    ^swapon --show
    print ""
    print "===== DISK ====="
    ^df -h /
  }
}

  let cores = if (['firefox' 'thunderbird' 'chromium'] | any {|p| $package | str downcase | str contains $p }) { 2 } else { 4 }
  print $"Using --cores=($cores)"

let build = (do { cd src; ^nix build --max-jobs 1 --cores $cores --impure --keep-going -L --no-link --fallback $".#($package)" } | complete)
  gha group "nix build" {
    $build.stdout | print
    $build.stderr | print
  }

let build_successful = $build.exit_code == 0

let job_url = (gha group "get job url" {
  mut url = $"($env.GITHUB_SERVER_URL)/($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)"
  try {
    for _ in 1..5 {
      let jobs = (^gh api $"/repos/($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)/jobs" | from json)
      let job = ($jobs.jobs | where name == $"build-($system)-($package)" | first)
      if ($job | is-not-null) {
        let base = $job.html_url
        let step = ($job.steps | where name == "Nix build" | get number? | first)
        $url = if ($step | is-not-null) { $"($base)#step:($step):1" } else { $base }
        break
      }
      sleep 2sec
    }
  }
  $url
})

gha group "generate build report" {
  let status = if $build_successful { ":white_check_mark: Success" } else { ":x: Failed" }
  let report_md = $"### `($system)` - `($package)`\n- Package: `($package)`\n- Status: ($status)\n- Logs: See [workflow run]($env.GITHUB_SERVER_URL)/($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)\n"

  $report_md | save -f $"build_report_($system)_($package).md"
  {
    md: $report_md
    successful: $build_successful
    system: $system
    package: $package
    job_url: $job_url
  } | to json | save -f $"build_report_($system)_($package).json"

  print $report_md
  $build_successful | to json -r | gha output successful
}

if not $build_successful { exit 1 }
