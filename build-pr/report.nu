use gha.nu *

let inputs = gha build-pr-inputs

let pr_enabled = ($env.PR_ENABLED == 'true')
let tg_enabled = ($env.TG_ENABLED == 'true')

let reports = (
    glob "build_report_*.json"
    | each {|path| open $path }
)

let total = ($reports | length)
let successful = ($reports | where {|r| $r.successful? == true } | length)
let failed = ($total - $successful)

let all_successful = ($total > 0 and $successful == $total)

let failed_reports = (
    $reports
    | where {|r| $r.successful? != true }
    | sort-by system package
)

let package_names = (
    $reports
    | get package
    | uniq
    | sort
)

let packages = (
    $package_names
    | each {|pkg|
        {
            name: $pkg
            reports: (
                $reports
                | where package == $pkg
                | sort-by successful system
            )
        }
    }
)

let pr_number = ($inputs."pr-number" | into string)

let pr_url = (
    $env.GITHUB_SERVER_URL
    + "/"
    + $inputs.repo
    + "/pull/"
    + $pr_number
)

let workflow_url = (
    $env.GITHUB_SERVER_URL
    + "/"
    + $env.GITHUB_REPOSITORY
    + "/actions/runs/"
    + $env.GITHUB_RUN_ID
)

let context = {
    all_successful: $all_successful
    successful: $successful
    failed: $failed
    total: $total
    repo: $inputs.repo
    pr_number: $pr_number
    pr_url: $pr_url
    workflow_url: $workflow_url
    packages: $packages
    failed_reports: ($failed_reports | first 20)
    failed_omitted: ([($failed - 20), 0] | math max)
}

let context_json = ($context | to json)

let template_dir = (
    $env.GITHUB_WORKSPACE
    | path join ".github" "templates"
)

let pr_template = ($template_dir | path join "report-pr.md")
let tg_template = ($template_dir | path join "report-tg.html")

gha group "generate PR report" {
  let result = (
      $context_json
      | ^tera --template $pr_template --stdin
      | complete
  )

    if $result.exit_code != 0 {
        error make {
            msg: $"Failed to render report-pr.md: ($result.stderr | str trim)"
        }
    }

    let report = $result.stdout

    if $pr_enabled {
        $report | save -f report.md
        print "Generated report.md"
    }

    print $report
    $report | gha step-summary

    $all_successful | to json -r | gha output success
}

if $pr_enabled {
    gha group "output PR report link" {
        let report_url = (
            "https://nightly.link/"
            + $env.GITHUB_REPOSITORY
            + "/actions/runs/"
            + $env.GITHUB_RUN_ID
            + "/report.md"
        )

        print ("Build report: [View full report](" + $report_url + ")")
    }
}

if $tg_enabled {
    gha group "generate Telegram notification" {
      let result = (
          $context_json
          | ^tera --template $tg_template --stdin --escape
          | complete
      )

        if $result.exit_code != 0 {
            error make {
                msg: $"Failed to render report-tg.html: ($result.stderr | str trim)"
            }
        }

        $result.stdout | save -f telegram-notification.txt

        print "Generated telegram-notification.txt"
    }
}
