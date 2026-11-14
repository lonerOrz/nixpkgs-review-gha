use gha.nu *

let inputs = gha build-pr-inputs

let packages = (
  $inputs.packages
  | split row -r '[\s,;]+'
  | where ($it | str trim | is-not-empty)
  | uniq
)

let requested_systems = (
  [
    {name: "x86_64-linux", enabled: ($inputs.x86_64-linux == "true" or $inputs.x86_64-linux == true)}
    {name: "aarch64-linux", enabled: ($inputs.aarch64-linux == "true" or $inputs.aarch64-linux == true)}
    {name: "x86_64-darwin", enabled: ($inputs.x86_64-darwin != "no")}
    {name: "aarch64-darwin", enabled: ($inputs.aarch64-darwin != "no")}
  ]
  | where enabled
  | get name
)

def to-matrix [provided: record, requested_systems: list<string>] {
  $provided
  | items {|pkg, systems|
    $systems
    | where $in in $requested_systems
    | each {|sys| {system: $sys, package: $pkg}}
  }
  | flatten
}

gha group "parse packages" {
  print $"packages: ($packages | to json -r)"
  print $"requested systems: ($requested_systems | to json -r)"

  mut matrix = (
    $packages
    | each {|pkg|
      $requested_systems
      | each {|sys| {system: $sys, package: $pkg}}
    }
    | flatten
  )

  if (
    ($packages | is-not-empty)
    and ($requested_systems | is-not-empty)
    and ($env.GITHUB_RUN_ID? | default "" | is-not-empty)
  ) {
    let head_result = (
      do -i {
        ^gh api $"repos/($inputs.repo)/pulls/($inputs.pr-number)" --jq '{sha: .head.sha, repo: .head.repo.full_name}'
      } | complete
    )

    if $head_result.exit_code != 0 {
      gha warning --title "failed to get PR head" \
        $"gh api failed, falling back to full matrix: ($head_result.stderr | str trim)"
    } else {
      let head = (
        try {
          $head_result.stdout | from json
        } catch {
          null
        }
      )

      if $head == null {
        gha warning --title "failed to parse PR head" \
          "gh api returned invalid JSON, falling back to full matrix."
      } else {
        let head_owner_repo = ($head.repo | default $inputs.repo)
        let head_sha = ($head.sha | default "")
        let flake_url = $"github:($head_owner_repo)/($head_sha)"

        if ($head_sha | is-empty) {
          gha warning --title "failed to get PR head SHA" \
            "PR head SHA is missing, falling back to full matrix."
        } else {
          let nix_args = [
            "--extra-experimental-features" "flakes nix-command"
            "--eval" "--strict" "--json" "--impure"
            "--argstr" "flake" $flake_url
            "--argstr" "packages" ($packages | to json -r)
            ($env.GITHUB_WORKSPACE | path join "pr-build-support.nix")
          ]

          # Do not expose GitHub tokens to PR-controlled Nix evaluation.
          if "GITHUB_TOKEN" in ($env | columns) {
            hide-env GITHUB_TOKEN
          }
          if "GH_TOKEN" in ($env | columns) {
            hide-env GH_TOKEN
          }

          let result = (do -i { ^nix-instantiate ...$nix_args } | complete)

          if $result.exit_code == 0 {
            let provided = ($result.stdout | from json)
            $matrix = (to-matrix $provided $requested_systems)
            print $"supported matrix: ($matrix | to json -r)"
          } else {
            gha warning --title "availability check failed" \
              $"nix-instantiate failed, falling back to full matrix: ($result.stderr | str substring 0..500 | str trim)"
          }
        }
      }
    }
  }

  print $"matrix: ($matrix | to json -r)"
  $matrix | to json -r | gha output matrix
}
