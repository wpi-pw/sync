#!/bin/bash

# WPI Sync
# by DimaMinka (https://dima.mk)
# https://github.com/wpi-pw/app

# Get config files and put to array
wpi_confs=()
for ymls in wpi-config/*
do
  wpi_confs+=("$ymls")
done

# Get wpi-source for yml parsing, noroot, errors etc
source <(curl -s https://raw.githubusercontent.com/wpi-pw/template-workflow/master/wpi-source.sh)

# sync environments
FROM=$1
TO=$2
local=""
# Source environment name
app_user=$(wpi_yq env.$FROM.app_user)
app_host=$(wpi_yq env.$FROM.app_host)
app_ip=$(wpi_yq env.$FROM.app_ip)
app_dir=$(wpi_yq env.$FROM.app_dir)
app_content=$(wpi_yq env.$FROM.app_content)
app_protocol=$(wpi_yq env.$FROM.app_protocol)
# Destination environment name
app_host_sync=$(wpi_yq env.$TO.app_host)
app_user_sync=$(wpi_yq env.$TO.app_user)
app_ip_sync=$(wpi_yq env.$TO.app_ip)
app_dir_sync=$(wpi_yq env.$TO.app_dir)
app_content_sync=$(wpi_yq env.$TO.app_content)
app_protocol_sync=$(wpi_yq env.$TO.app_protocol)
# sync flags
sync_dirs=()
cur_flags=$3
wip_flag=${cur_flags//-}
sync_remote="false"
# Vars with messages
cur_flags_message="❌  Current flags not available"
local_message="❌  Local env can't be remotely, please remove the flag 'R'"
cur_env_message="❌  Current environments not supported"
remote_message="🔄 Approve ${bold}SYNC️${normal}to remote app![y/N] "
db_message="🔄 Would you really like to ⚠️${bold}reset ${normal}the $TO database($app_host_sync)
 and ${bold}push ${normal}from $FROM($app_host)? [y/N] "

# Check for required environments and flags
if [[ -z "$FROM" || -z "$TO" ]]; then
  echo "❌  Please put ${bold}2${normal} environments" && exit 1
elif [[ -z "$(wpi_yq "env.$FROM")" || -z "$(wpi_yq "env.$TO")" ]]; then
  echo "❌  ${bold}$FROM${normal} or ${bold}$TO${normal} not exist in env config" && exit 1
elif [[ -z "$wip_flag" ]]; then
  echo "❌  ${bold}Flags${normal} not exist, supported: ${bold}d l m p t u" && exit 1
fi

# Make sure both environments are available before we continue
avail_check() {
  local avail
  # current environment name
  cur_avail=""
  cur_avail=$1
  # check for local environment
  if [[ "$cur_avail" == "local" ]]; then
    # check local environment connection
    avail=$(wp option get home 2>&1)
  else
    # check remote environment connection
    avail=$(wp "@$TO" option get home 2>&1)
  fi
  # message output
  if [[ $avail == *"Error"* ]]; then
    echo "❌  Unable to connect to $cur_avail" && exit 1
  else
    echo "✅  Able to connect to $cur_avail"
  fi
};
avail_check $FROM && avail_check $TO

for ((i=0; i<${#wip_flag}; i++)); do
  # Parse the flags and setup vars
  case "${wip_flag:$i:1}" in
    R)  sync_remote="remote" && read -r -p "$remote_message" response;; # sync remote environments
    d)  sync_db="true" && read -r -p "$db_message" db_response;;        # sync database
    l)  sync_dirs+=("languages");;                                      # sync languages
    m)  sync_dirs+=("mu-plugins");;                                     # sync must use plugins
    p)  sync_dirs+=("plugins");;                                        # sync plugins
    t)  sync_dirs+=("themes");;                                         # sync themes
    u)  sync_dirs+=("uploads");;                                        # sync uploads
    *)  echo $cur_flags_message && exit 1 ;;
  esac
done

for i in "${!sync_dirs[@]}"; do
  # Default bedrock content path
  def_path="/web/app/"
  # SSH vars for source/destination environments
  from_ssh="$app_user@$app_ip"
  to_ssh="$app_user_sync@$app_ip_sync"
  # Get current content type path: plugins, uploads etc
  cur_type=${sync_dirs[$i]}
  cur_path="/$cur_type/"
  # Path vars for source environment
  from_env=${app_dir%/}${app_content%/}$cur_path
  from_env_def="${app_dir%/}${def_path%/}$cur_path"
  #  vars fo vars for destination environment
  to_env=${app_dir_sync%/}${app_content_sync%/}$cur_path
  to_env_def="$to_ssh:${app_dir_sync%/}${def_path%/}$cur_path"
  # Var helper for default content path
  def_type="false"
  if [[ "$cur_type" == "mu-plugins" || "$cur_type" == "plugins" || "$cur_type" == "themes" ]]; then
    def_type="true"
  fi
  # Check supported environments and setup the env by type
  case "$FROM-$TO-$sync_remote-$def_type" in
    local-dev-false-false)     local="true"; to_env="$to_ssh:$to_env";;
    local-dev-false-true)      local="true"; to_env=$to_env_def;;
    local-staging-false-false) local="true"; to_env="$to_ssh:$to_env";;
    local-staging-false-true)  local="true"; to_env=$to_env_def;;
    *-local-false-false)       local="true"; from_env="$from_ssh:$from_env";;
    *-local-false-true)        local="true"; from_env="$from_ssh:$from_env_def";;
    local-*-remote-false)      local="true"; to_env="$to_ssh:$to_env";;
    local-*-remote-true)       local="true"; to_env=$to_env_def;;
    *-local-remote-*)          echo $local_message && exit 1 ;;
    $FROM-$TO-remote-false)    remote="true"; to_env="$from_ssh:$to_env";;
    $FROM-$TO-remote-true)     remote="true"; from_env="$from_env_def"; to_env="$to_env_def";;
    *)                         echo $cur_env_message && exit 1 ;;
  esac
  if [[ "$local" == "true" ]]; then
    # Local environment pull/push
    rsync -avz -P --del $from_env $to_env
  elif [[ "$remote" == "true" && "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Remote environments sync
    ssh -o ForwardAgent=yes $from_ssh "rsync -aze 'ssh -o StrictHostKeyChecking=no' -P --del $from_env $to_env"
  fi
done

if [[ "$db_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  # Export/import database, run search & replace
  wp_flags="--all-tables --quiet"
  wp "@$TO" db export &&
  wp "@$TO" db reset --yes &&
  wp "@$FROM" db export - | wp "@$TO" db import - &&
  echo "🔄 Search replace ${bold}processing..." &&
  wp "@$TO" search-replace "$app_protocol://$app_host" "$app_protocol_sync://$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_protocol:\/\/$app_host" "$app_protocol_sync:\/\/$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_protocol%3A%2F%2F$app_host" "$app_protocol_sync%3A%2F%2F$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_host" "$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_dir" "$app_dir_sync" $wp_flags &&
  wp "@$TO" search-replace "@www" "@" $wp_flags &&
  echo "✅  Search replace ${bold}done..."
fi
echo -e "\n\n🔄  Sync from $FROM to $TO complete.\n    ${bold}$TOSITE${normal}\n"
