export def "gha group" [name: string, block: closure] {
  print $"::group::($name)"
  let result = do $block
  print "::endgroup::"
  $result
}

def "gha log" [level: string, args: record, msg: string] {
  $args
  | compact
  | transpose name value
  | each { $"($in.name)=($in.value)" }
  | str join ","
  | print $"::($level) ($in)::($msg)"
}

export def "gha warning" [--title: string, msg: string] {
  gha log warning { title: $title } $msg
}

export def "gha error" [--title: string, msg: string] {
  gha log error { title: $title } $msg
}

export def "gha output" [name: string] {
  $"($name)=($in)\n" | save -ra $env.GITHUB_OUTPUT
}

export def "gha step-summary" [] {
  save -rf $env.GITHUB_STEP_SUMMARY
}

export def "gha build-pr-inputs" [] {
  $env.INPUTS
  | from json
  | update "pr-number" { into int }
}
