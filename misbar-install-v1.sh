#!/bin/bash

fail() {
  printf "%s\n" "$@" >&2
  exit 1
}

if [ -z "${BASH_VERSION:-}" ]; then
  fail "Bash is required to run this script"
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required to run this script"
fi

# Check if the `lsof` command exists in PATH, if not use `/usr/sbin/lsof` if possible
LSOF_PATH=""
if command -v lsof >/dev/null 2>&1; then
  LSOF_PATH=$(command -v lsof)
elif command -v /usr/sbin/lsof >/dev/null 2>&1; then
  LSOF_PATH="/usr/sbin/lsof"
fi

server_url=""
onboarding_id=""
token=""

help() {
  echo "Usage: sudo ./misbar-install-v3.sh <arguments>"
  echo ""
  echo "Arguments:"
  echo "  --id=<value>   Onboarding ID"
  echo "  --token=<value>   Authentication token"
  exit 1
}

ensure_argument() {
  if [ -z "$1" ]; then
    echo "Error: Missing value for $2"
    help
  fi
}

# Parse command line arguments
for i in "$@"; do
  case $i in
  --id=*)
    shift
    onboarding_id="${i#*=}"
    ;;
  --token=*)
    shift
    token="${i#*=}"
    ;;
  --server-url=*)
    shift
    server_url="${i#*=}"
    ;;
  --help)
    help
    ;;
  *)
    echo "Unknown option: $i"
    help
    ;;
  esac
done


ensure_argument "$server_url" "--url"
ensure_argument "$onboarding_id" "--id"
ensure_argument "$token" "--token"

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  help
fi

OS="$(uname)"
ARCH="$(uname -m)"
os=linux
arch=amd64
if [ "${OS}" == "Linux" ]; then
  if [ "${ARCH}" == "aarch64" ]; then
    arch=arm64
  fi
else
  fail "This script is only supported on Linux"
fi

# Constants
PACKAGE_NAME="misbar"
DOWNLOAD_BASE="https://github.com/misbar-tech/misbar-agent-releases/releases/download"
MISBAR_USER="misbar"
TMP_DIR=${TMPDIR:-"/tmp"}
PREREQS="curl printf $SVC_PRE sed uname cut"
SCRIPT_NAME="$0"
INDENT_WIDTH='  '
indent=""
MISBAR_YML_PATH="/etc/misbar/config.yaml"
package_type="deb"

# Determine if we need service or systemctl for prereqs
if command -v systemctl > /dev/null 2>&1; then
  SVC_PRE=systemctl
elif command -v service > /dev/null 2>&1; then
  SVC_PRE=service
fi

# Colors
num_colors=$(tput colors 2>/dev/null)
if test -n "$num_colors" && test "$num_colors" -ge 8; then
  bold="$(tput bold)"
  underline="$(tput smul)"
  # standout can be bold or reversed colors dependent on terminal
  standout="$(tput smso)"
  reset="$(tput sgr0)"
  bg_black="$(tput setab 0)"
  bg_blue="$(tput setab 4)"
  bg_cyan="$(tput setab 6)"
  bg_green="$(tput setab 2)"
  bg_magenta="$(tput setab 5)"
  bg_red="$(tput setab 1)"
  bg_white="$(tput setab 7)"
  bg_yellow="$(tput setab 3)"
  fg_black="$(tput setaf 0)"
  fg_blue="$(tput setaf 4)"
  fg_cyan="$(tput setaf 6)"
  fg_green="$(tput setaf 2)"
  fg_magenta="$(tput setaf 5)"
  fg_red="$(tput setaf 1)"
  fg_white="$(tput setaf 7)"
  fg_yellow="$(tput setaf 3)"
fi

if [ -z "$reset" ]; then
  sed_ignore=''
else
  sed_ignore="/^[$reset]+$/!"
fi


# Helper Functions
printf() {
  if command -v sed >/dev/null; then
    command printf -- "$@" | sed -r "$sed_ignore s/^/$indent/g"  # Ignore sole reset characters if defined
  else
    # Ignore $* suggestion as this breaks the output
    # shellcheck disable=SC2145
    command printf -- "$indent$@"
  fi
}

increase_indent() { indent="$INDENT_WIDTH$indent" ; }
decrease_indent() { indent="${indent#*"$INDENT_WIDTH"}" ; }

# Color functions reset only when given an argument
bold() { command printf "$bold$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
underline() { command printf "$underline$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
standout() { command printf "$standout$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
# Ignore "parameters are never passed"
# shellcheck disable=SC2120
reset() { command printf "$reset$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_black() { command printf "$bg_black$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_blue() { command printf "$bg_blue$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_cyan() { command printf "$bg_cyan$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_green() { command printf "$bg_green$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_magenta() { command printf "$bg_magenta$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_red() { command printf "$bg_red$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_white() { command printf "$bg_white$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
bg_yellow() { command printf "$bg_yellow$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_black() { command printf "$fg_black$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_blue() { command printf "$fg_blue$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_cyan() { command printf "$fg_cyan$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_green() { command printf "$fg_green$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_magenta() { command printf "$fg_magenta$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_red() { command printf "$fg_red$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_white() { command printf "$fg_white$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }
fg_yellow() { command printf "$fg_yellow$*$(if [ -n "$1" ]; then command printf "$reset"; fi)" ; }

# Intentionally using variables in format string
# shellcheck disable=SC2059
info() { printf "$*\\n" ; }
# Intentionally using variables in format string
# shellcheck disable=SC2059
warn() {
  increase_indent
  printf "$fg_yellow$*$reset\\n"
  decrease_indent
}
# Intentionally using variables in format string
# shellcheck disable=SC2059
error() {
  increase_indent
  printf "$fg_red$*$reset\\n"
  decrease_indent
}

succeeded() {
  increase_indent
  success "Succeeded!"
  decrease_indent
}

# Intentionally using variables in format string
# shellcheck disable=SC2059
success() { printf "$fg_green$*$reset\\n" ; }
# Ignore 'arguments are never passed'
# shellcheck disable=SC2120
prompt() {
  if [ "$1" = 'n' ]; then
    command printf "y/$(fg_red '[n]'): "
  else
    command printf "$(fg_green '[y]')/n: "
  fi
}

update_step_progress() {
  local STATUS="$1" # "RUNNING" | "PENDING" | "DELETED"
  local data="{\"status\":\"${STATUS}\", \"agent_uuid\":\"${onboarding_id}\", \"agent_token\":\"${token}\"}"
  curl --request PUT \
    --url "$server_url/api/onboarding" \
    --header "Content-Type: application/json" \
    --data "$data" \
    --output /dev/null \
    --no-progress-meter \
    --fail
}

# latest_version gets the tag of the latest release, without the v prefix.
latest_version()
{
  curl -sSL https://api.github.com/repos/misbar-tech/misbar-agent-releases/releases/latest | \
    grep "\"tag_name\"" | \
    sed -r 's/ *"tag_name": "v([0-9]+\.[0-9]+\.[0-9]+)",/\1/'
}

set_download_urls()
{
  if [ -z "$url" ] ; then
    if [ -z "$version" ] ; then
      version=$(latest_version)
    fi

    if [ -z "$version" ] ; then
      error_exit "$LINENO" "Could not determine version to install"
    fi

    if [ -z "$base_url" ] ; then
      base_url=$DOWNLOAD_BASE
    fi

    agent_download_url="$base_url/v$version/${PACKAGE_NAME}_v${version}_linux_${arch}.${package_type}"
    out_file_path="/tmp/${PACKAGE_NAME}_v${version}_linux_${arch}.${package_type}"
  else
    agent_download_url="$url"
    out_file_path="/tmp/${PACKAGE_NAME}_v${version}_linux_${arch}.${package_type}"
  fi

  update_step_progress "URLSET"
}

# This will install the package by downloading the archived agent,
# extracting the binaries, and then removing the archive.
install_package()
{
  banner "Installing Misbar Agent"
  increase_indent

  info "Downloading package..."
  eval curl -L "$agent_download_url" -o "$out_file_path" --progress-bar --fail || error_exit "$LINENO" "Failed to download package"
  succeeded
  update_step_progress "DOWNLOADED"

  info "Installing package..."
  # if target install directory doesn't exist and we're using dpkg ensure a clean state 
  # by checking for the package and running purge if it exists.
  if [ ! -d "/etc/misbar" ] && [ "$package_type" = "deb" ]; then
    update_step_progress "INSTALLING"
    dpkg -s "misbar" > /dev/null 2>&1 && dpkg --purge "misbar" > /dev/null 2>&1
  fi

  unpack_package || error_exit "$LINENO" "Failed to extract package"
  succeeded

  # If an endpoint was specified, we need to write the misbar.yaml
  if [ -n "$onboarding_id" ]; then
    info "Creating misbar yaml..."
    update_step_progress "CREATCONFIG"
    create_misbar_yml "$MISBAR_YML_PATH"
    succeeded
  fi

  if [ "$SVC_PRE" = "systemctl" ]; then
    if [ "$(systemctl is-enabled misbar)" = "enabled" ]; then
      # The unit is already enabled; It may be running, too, if this was an upgrade.
      # We'll want to restart, which will start it if it wasn't running already,
      # and restart in the case that this was an upgrade on a running agent.
      info "Restarting service..."
      systemctl restart misbar > /dev/null 2>&1 || error_exit "$LINENO" "Failed to restart service"
      succeeded
    else
      info "Enabling service..."
      systemctl enable --now misbar > /dev/null 2>&1 || error_exit "$LINENO" "Failed to enable service"
      succeeded
    fi
  else
    case "$(service misbar status)" in
      *running*)
        # The service is running.
        # We'll want to restart.
        info "Restarting service..."
        service misbar restart > /dev/null 2>&1 || error_exit "$LINENO" "Failed to restart service"
        succeeded
        ;;
      *)
        info "Enabling and starting service..."
        chkconfig misbar on > /dev/null 2>&1 || error_exit "$LINENO" "Failed to enable service"
        service misbar start > /dev/null 2>&1 || error_exit "$LINENO" "Failed to start service"
        succeeded
        ;;
    esac
  fi

  success "Misbar Agent installation complete!"
  update_step_progress "INSTALLED"
  decrease_indent
}

unpack_package()
{
  update_step_progress "UNPACKINGPKG"
  case "$package_type" in
    deb)
      dpkg --force-confold -i "$out_file_path" > /dev/null || error_exit "$LINENO" "Failed to unpack package"
      ;;
    *)
      error "Unrecognized package type"
      return 1
      ;;
  esac
  return 0
}

# create_misbar_yml creates the misbar.yml at the specified path, containing agent information.
create_misbar_yml()
{
  misbar_yml_path="$1"
  if [ ! -f "$misbar_yml_path" ]; then
    # Note here: We create the file and change permissions of the file here BEFORE writing info to it
    # We do this because the file may contain a secret key, so we want 0 window when the
    # file is readable by anyone other than the agent & root
    command mkdir -p $(dirname $misbar_yml_path) && touch $misbar_yml_path
    chmod 0640 "$misbar_yml_path"

    command printf 'endpoint: "%s"\n' "$server_url" > "$misbar_yml_path"
    [ -n "$onboarding_id" ] && command printf 'onboarding_id: "%s"\n' "$onboarding_id" >> "$misbar_yml_path"
    [ -n "$token" ] && command printf 'auth_token: "%s"\n' "$token" >> "$misbar_yml_path"
  fi
}

# This will display the results of an installation
display_results()
{
    banner 'Information'
    increase_indent
    info "Agent Home:         $(fg_cyan "/etc/misbar")$(reset)"
    info "Agent Config:       $(fg_cyan "/etc/misbar/config.yaml")$(reset)"
    if [ "$SVC_PRE" = "systemctl" ]; then
      info "Start Command:      $(fg_cyan "sudo systemctl start misbar")$(reset)"
      info "Stop Command:       $(fg_cyan "sudo systemctl stop misbar")$(reset)"
    else
      info "Start Command:      $(fg_cyan "sudo service misbar start")$(reset)"
      info "Stop Command:       $(fg_cyan "sudo service misbar stop")$(reset)"
    fi
    info "Logs Command:       $(fg_cyan "sudo tail -F /etc/misbar/log/misbar.log")$(reset)"
    decrease_indent

    banner 'Support'
    increase_indent
    info "For more information on configuring the agent, see the docs:"
    increase_indent
    info "$(fg_cyan "https://github.com/misbar-tech/misbar-agent-releases/tree/main")$(reset)"
    decrease_indent
    info "If you have any other questions please contact us at $(fg_cyan support@misbar.tech)$(reset)"
    increase_indent
    decrease_indent
    decrease_indent

    banner "$(fg_green Installation Complete!)"
    return 0
}

misbar_banner()
{
    fg_white "  ___      ___   __      ________  _______       __        _______   \n"
    fg_white " |   \    /   | |  \    /        )|   _   \     /  \      /       \  \n"
    fg_white "  \   \  //   | ||  |  (:   \___/ (. |_)  :)   /    \    |:        | \n"
    fg_white "  /\\  \/.    | |:  |   \___  \   |:     \/   /' /\  \   |_____/   ) \n"
    fg_white " |: \.        | |.  |    __/  \\  (|  _  \\  //  __'  \   //      /  \n"
    fg_white " |.  \    /:  | /\  |\  /  \   :) |: |_)  :)/   /  \\  \ |:  __   \  \n"
    fg_white " |___|\__/|___|(__\_|_)(_______/  (_______/(___/    \___)|__|  \___) \n"
                                                               
    reset
}

separator() { printf "===================================================\\n" ; }

banner()
{
  printf "\\n"
  separator
  printf "| %s\\n" "$*" ;
  separator
}

# This will check if the current environment has
# all required shell dependencies to run the installation.
dependencies_check() {
  info "Checking for script dependencies..."
  FAILED_PREREQS=''
  for prerequisite in $PREREQS; do
    if command -v "$prerequisite" >/dev/null; then
      continue
    else
      if [ -z "$FAILED_PREREQS" ]; then
        FAILED_PREREQS="${fg_red}$prerequisite${reset}"
      else
        FAILED_PREREQS="$FAILED_PREREQS, ${fg_red}$prerequisite${reset}"
      fi
    fi
  done

  if [ -n "$FAILED_PREREQS" ]; then
    failed
    error_exit "$LINENO" "The following dependencies are required by this script: [$FAILED_PREREQS]"
  fi
  succeeded
}

# This will check to ensure dpkg is installed on the system
package_type_check()
{
  info "Checking for package manager..."
  if command -v dpkg > /dev/null 2>&1; then
      succeeded
  else
      failed
      error_exit "$LINENO" "Could not find dpkg on the system"
  fi
}

# This will check all prerequisites before running an installation.
check_prereqs()
{
  banner "Checking Prerequisites"
  increase_indent
  package_type_check
  dependencies_check
  success "Prerequisite check complete!"
  decrease_indent
}

main()
{
  misbar_banner
  check_prereqs
  set_download_urls
  install_package
  display_results
}

main