use gha.nu *

let inputs = gha build-pr-inputs

if $env.GH_TOKEN_ENABLED != 'true' { exit }

gha group "ensure build-pr-success label exists" {
  try { ^gh label create "build-pr-success" --color "28a745" -R $inputs.repo }
}

gha group "post comment and manage labels" {
  ^gh pr comment $"($inputs."pr-number")" -R $inputs.repo -F report.md

  if $env.BUILD_SUCCESS == 'true' {
    ^gh pr edit $"($inputs."pr-number")" -R $inputs.repo --add-label "build-pr-success"
  } else {
    try { ^gh pr edit $"($inputs."pr-number")" -R $inputs.repo --remove-label "build-pr-success" }
  }
}
