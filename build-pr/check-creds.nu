use gha.nu *

gha group "check credentials" {
  let gh_token = not ($env.GH_TOKEN_SECRET? | is-empty)
  let cachix = not ($env.CACHIX_AUTH_TOKEN? | is-empty)
  let tg = (not ($env.TG_BOT_TOKEN? | is-empty)) and (not ($env.TG_CHAT_ID? | is-empty))

  if not $gh_token {
    gha warning --title "GH_TOKEN not configured" "PR comment and label operations will be skipped."
  }
  if not $tg {
    gha warning --title "Telegram not configured" "TG_BOT_TOKEN or TG_CHAT_ID secret is not configured. Telegram notification will be skipped."
  }

  $gh_token | to json -r | gha output gh_token
  $cachix | to json -r | gha output cachix
  $tg | to json -r | gha output tg
}
