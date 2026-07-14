use gha.nu *

def escape_html [] {
  $in
  | str replace -a '&' '&amp;'
  | str replace -a '<' '&lt;'
  | str replace -a '>' '&gt;'
  | str replace -a '"' '&quot;'
}

let inputs = gha build-pr-inputs

gha group "generate combined report" {
  let reports = (ls build_report_*.json | get name | each { open $in })
  let packages = ($reports | get package | uniq)

  mut report = "## Build Results\n\n"
  $report = ($report + $"Generated using [`nixpkgs-review-gha`]\(https://github.com/Defelo/nixpkgs-review-gha\)\n")
  $report = ($report + $"Repository: ($inputs.repo)\n")
  $report = ($report + $"PR: #($inputs."pr-number")\n")
  $report = ($report + $"Workflow: [($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)]\(($env.GITHUB_SERVER_URL)/($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)\)\n\n")

  for pkg in $packages {
    $report = ($report + $"### `($pkg)`\n\n")
    $report = ($report + "| System | Status | Log |\n")
    $report = ($report + "|--------|--------|-----|\n")
    for r in ($reports | where package == $pkg) {
      let status = if $r.successful { ":white_check_mark: Success" } else { ":x: Failed" }
      if ($r.job_url | is-not-empty) {
        $report = ($report + $"| ($r.system) | ($status) | [log]\(($r.job_url)\) |\n")
      } else {
        $report = ($report + $"| ($r.system) | ($status) | |\n")
      }
    }
    $report = ($report + "\n")
  }

  let all_successful = ($reports | get successful | all { $in })
  $report | save -f report.md
  print $report

  $report
  | str replace -r '^.*' $"$0 for [#($inputs."pr-number")]\(($env.GITHUB_SERVER_URL)/($inputs.repo)/pull/($inputs."pr-number")\)"
  | gha step-summary

  $all_successful | to json -r | gha output success
}

gha group "output report link" {
  print "======================================================"
  print "Copy the line below and paste it into the PR comment:"
  print "======================================================"
  print ""
  print $"Build report: [View full report]\(https://nightly.link/($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)/report.md\)"
  print ""
  print "======================================================"
}

if $env.TG_ENABLED == 'true' {
  gha group "generate telegram summary" {
    let reports = (ls build_report_*.json | get name | each { open $in })
    let total = ($reports | length)
    let successful = ($reports | where successful | length)
    let workflow_url = $"($env.GITHUB_SERVER_URL)/($env.GITHUB_REPOSITORY)/actions/runs/($env.GITHUB_RUN_ID)"
    let pr_url = $"https://github.com/($inputs.repo)/pull/($inputs."pr-number")"

    mut tg = $"<b><a href=\"($pr_url)\">($inputs.repo)#($inputs."pr-number")</a></b>\n\n"
    if $successful == $total {
      $tg = ($tg + $"✅ <b>($successful)/($total)</b> builds passed\n")
    } else {
      $tg = ($tg + $"❌ <b>($successful)/($total)</b> builds passed\n")
    }

    if $successful < $total {
      $tg = ($tg + "\nFailed builds:\n")
      let failed = ($reports | where successful == false | sort-by system)
      let max = 20
      mut count = 0
      let total_failed = ($total - $successful)
      for r in $failed {
        $count = ($count + 1)
        if $count > $max {
          $tg = ($tg + $"… and ($total_failed - $max) more\n")
          break
        }
        let sys = ($r.system | escape_html)
        let pkg = ($r.package | escape_html)
        let url = ($r.job_url | escape_html)
        if ($url | is-not-empty) {
          $tg = ($tg + $"• ($sys) · <code>($pkg)</code> — <a href=\"($url)\">log</a>\n")
        } else {
          $tg = ($tg + $"• ($sys) · <code>($pkg)</code>\n")
        }
      }
    }

    $tg = ($tg + $"\n<a href=\"($workflow_url)\">Build details</a>\n")
    $tg | save -f telegram-notification.txt
  }
}
