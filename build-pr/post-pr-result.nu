use gha.nu *

let inputs = gha build-pr-inputs

if $env.GH_TOKEN_ENABLED != 'true' {
    exit
}

# Post PR comment only when enabled.
if $env.PR_ENABLED == 'true' {
    gha group "post PR comment" {
        ^gh pr comment $"($inputs."pr-number")" -R $inputs.repo -F report.md
    }
}

# Manage build status label independently of PR comments.
gha group "manage build-pr-success label" {
    if $env.BUILD_SUCCESS == 'true' {
        ^gh pr edit $"($inputs."pr-number")" -R $inputs.repo --add-label "build-pr-success"
    } else {
        ^gh pr edit $"($inputs."pr-number")" -R $inputs.repo --remove-label "build-pr-success"
    }
}
