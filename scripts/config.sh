# Your own signing and device settings, which the repo never holds. Sourced by scripts/platform.sh and
# scripts/flavor.sh (so by every build, run and seed script). Each SP_ variable comes from the
# environment or, if unset there, from config/local.env at the repo root (gitignored; copy
# config/local.env.example). Lines are KEY=value, no quotes or shell expansion; # starts a comment.
#   SP_TEAM        your Apple developer team ID (signs the device app; also the entitlements' team)
#   SP_SIGN_ID     your Apple Development codesign identity (its SHA-1 hash, from
#                  `security find-identity -v -p codesigning`)
#   SP_BUNDLE_ID   the device app's bundle ID, by convention <TEAMID>.slashplayed. Changing it gives the
#                  app a new data container on the device, so every game file is copied again.
#   SP_DEVICE      the device's UDID; else SP_DEVICE_XROS or SP_DEVICE_IOS for the platform being
#                  built; else (sp_need_device) the one paired device of that platform devicectl lists
#                  (for ios an iPad or an iPhone).
#   SP_INSTALL     the game install (scripts/flavor.sh defaults it to /Applications/World of Warcraft).
# sp_need <var>... stops the script with a fix-it message if any is unset. Scripts call it (and
# sp_need_device) only where they use the value, so a build that doesn't install needs no device.
if [ -z "${_sp_config:-}" ]; then
  _sp_config=1
  SP_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null) ||
    { echo "scripts/config.sh: can't find the repo root (run the scripts from inside the repo)" >&2; exit 1; }
  if [ -f "$SP_ROOT/config/local.env" ]; then
    _n=0
    while IFS= read -r _line || [ -n "$_line" ]; do
      _n=$((_n + 1))
      case $_line in ''|'#'*) continue ;; esac
      _k=${_line%%=*}; _v=${_line#*=}
      case $_k in
        SP_*) case $_k in *[!A-Z0-9_]*) _k= ;; esac ;;
        *) _k= ;;
      esac
      [ -n "$_k" ] && [ "$_k" != "$_line" ] ||
        { echo "config/local.env line $_n isn't SP_NAME=value: $_line" >&2; exit 1; }
      # The environment wins over the file.
      eval "_cur=\${$_k-}"
      [ -n "$_cur" ] || { eval "$_k=\$_v"; export "$_k"; }
    done < "$SP_ROOT/config/local.env"
  fi
fi

sp_need() {
  for _k in "$@"; do
    eval "_cur=\${$_k-}"
    [ -n "$_cur" ] && continue
    echo "$_k isn't set. Put it in config/local.env (copy config/local.env.example) or the environment." >&2
    exit 1
  done
}

# sp_need_device sets SP_DEVICE for SP_PLATFORM (call it after sourcing scripts/platform.sh): SP_DEVICE,
# else SP_DEVICE_XROS or SP_DEVICE_IOS, else the only paired physical device of the platform (a Vision
# Pro for xros, an iPad or iPhone for ios) that `devicectl list devices` shows. Stops if there's none or
# several (an iPad and an iPhone both paired: set SP_DEVICE_IOS, or SP_DEVICE for one run).
sp_need_device() {
  if [ -z "${SP_DEVICE:-}" ]; then
    case $SP_PLATFORM in
      xros) SP_DEVICE=${SP_DEVICE_XROS:-} ;;
      ios) SP_DEVICE=${SP_DEVICE_IOS:-} ;;
    esac
  fi
  if [ -z "${SP_DEVICE:-}" ]; then
    _list=$(mktemp)
    xcrun devicectl list devices --json-output "$_list" >/dev/null 2>&1 ||
      { rm -f "$_list"; echo "devicectl couldn't list devices (is Xcode installed and selected? xcode-select -p)" >&2; exit 1; }
    # One "<udid> <name>" line per paired physical device of the platform.
    _found=$(python3 -c 'import json, sys
platform, types = {"xros": ("visionOS", None), "ios": ("iOS", ("iPad", "iPhone"))}[sys.argv[2]]
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") == platform and (types is None or hw.get("deviceType") in types) \
            and hw.get("reality") != "simulated" and conn.get("pairingState") == "paired":
        print(hw["udid"], d.get("deviceProperties", {}).get("name", ""))' "$_list" "$SP_PLATFORM")
    rm -f "$_list"
    _noun=$([ "$SP_PLATFORM" = ios ] && echo "iPad or iPhone" || echo "Vision Pro")
    case $(printf '%s' "$_found" | grep -c .) in
      0) echo "no $_noun is paired with this Mac: pair one in Xcode (Xcode > Open Developer Tool > Device Hub)," \
           "or set SP_DEVICE" >&2; exit 1 ;;
      1) SP_DEVICE=${_found%% *}; echo "device: ${_found#* } (the only paired $_noun)" >&2 ;;
      *) echo "more than one $_noun is paired; set SP_DEVICE (or SP_DEVICE_$(echo "$SP_PLATFORM" | tr a-z A-Z)" \
           "in config/local.env) to one of:" >&2
         printf '%s\n' "$_found" | sed 's/^/  /' >&2; exit 1 ;;
    esac
  fi
  export SP_DEVICE
}
