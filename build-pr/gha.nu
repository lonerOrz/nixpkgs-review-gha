# GHA workflow command helpers.
# All exported commands are pipeline-friendly where it makes sense.

# Escape workflow command property values.
def escape-property [value: string] {
  $value
  | str replace -a "%" "%25"
  | str replace -a "\r" "%0D"
  | str replace -a "\n" "%0A"
  | str replace -a ":" "%3A"
  | str replace -a "," "%2C"
}

# Escape workflow command message data.
def escape-data [value: string] {
  $value
  | str replace -a "%" "%25"
  | str replace -a "\r" "%0D"
  | str replace -a "\n" "%0A"
}

export def "gha group" [name: string, block: closure] {
  print $"::group::($name)"
  let result = do $block
  print "::endgroup::"
  $result
}

def "gha log" [level: string, args: record, msg: string] {
  let params = (
    $args
    | compact
    | transpose name value
    | each {|item|
      $"($item.name)=$(escape-property ($item.value | into string))"
    }
    | str join ","
  )

  let message = escape-data $msg

  if ($params | is-empty) {
    print $"::($level)::($message)"
  } else {
    print $"::($level) ($params)::($message)"
  }
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
  save -raf $env.GITHUB_STEP_SUMMARY
}

# Parse workflow_dispatch inputs for build-pr.
export def "gha build-pr-inputs" [] {
  $env.INPUTS
  | from json
  | update "pr-number" { into int }
}
