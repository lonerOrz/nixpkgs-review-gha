use gha.nu *

let inputs = gha build-pr-inputs

gha group "parse packages" {
  let packages = $inputs.packages
    | split row -r '[\s,;]+'
    | where ($it | str trim | is-not-empty)
    | to json -r

  $packages | gha output packages
}
