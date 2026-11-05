# Computes which systems a PR flake exposes each package on.
#
# Mirrors `nix build .#attr` package lookup:
#   packages.<system>
# Systems the flake does not declare are never evaluated, avoiding
# `attribute '<system>' missing` errors.
#
# Usage:
#   nix-instantiate --eval --strict --json --impure \
#     --argstr flake "github:owner/repo/<head-sha>" \
#     --argstr packages '["wsl-open","nmag"]' \
#     pr-build-support.nix
#
# Output: { "<package>": [ "<system>", ... ], ... }
{
  flake,
  packages,
}:
let
  inherit (builtins)
    attrNames
    filter
    fromJSON
    getAttr
    getFlake
    hasAttr
    isAttrs
    listToAttrs
    map
    split
    typeOf
    ;

  pipe = builtins.foldl' (acc: f: f acc);

  unique = list:
    attrNames (listToAttrs (map (x: { name = x; value = null; }) list));

  fl = getFlake flake;
  requested = fromJSON packages;

  # Return systems declared under fl.packages, or [] if the output is missing.
  declared = output:
    if isAttrs (fl.${output} or null)
    then attrNames fl.${output}
    else [ ];

  # Systems the flake explicitly exposes packages on.
  checkableSystems = unique (declared "packages");

  # True if `path` (possibly dotted) exists in `set`.
  # Tries the whole path as a single attribute name first, then falls back to component-wise lookup.
  # Flake attr names can be quoted names containing dots.
  hasAttrPath = set: path:
    let
      components = pipe path [
        (split "\\.")
        (filter (x: typeOf x == "string"))
        (filter (x: x != ""))
      ];

      go = s: comps:
        if comps == [ ] then true
        else if !isAttrs s then false
        else
          let
            key = builtins.head comps;
            rest = builtins.tail comps;
          in
          if hasAttr key s
          then go (getAttr key s) rest
          else false;
    in
    if !isAttrs set then false
    else if hasAttr path set then true
    else components != [ ] && go set components;

  # Systems on which the flake exposes the given package.
  provided = package:
    filter
      (s: hasAttrPath (fl.packages.${s} or null) package)
      checkableSystems;

in
listToAttrs (
  map (package: {
    name = package;
    value = provided package;
  }) requested
)
