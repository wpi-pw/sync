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

# text font weight
bold=$(tput bold)
normal=$(tput sgr0)

cur_args=()
sync_args=(source destination flags)

for i in "${!sync_args[@]}"; do
  if [[ "${sync_args[$i]}" != "flags" ]]; then
    # Get top keys from env config, local excluded
    mapfile -t env_alias < <(wpi_yq "env" "top_keys")
    # Make wp cli alias in wp-cli.yml from for env config
    for a in "${!env_alias[@]}"
    do
      echo "[$((a+1))] ${env_alias[$a]}"
    done

    read -n 2 -ep "→ ${bold}Use available option from the list of ${sync_args[$i]}: " cur_a

    cur_args+=(${env_alias[$((cur_a-1))]}) && clear
  else

    echo -e \
    "Available sync flags:\n" \
    "D - sync database with ignoring db connection checking\n" \
    "P - sync single plugin\n" \
    "R - sync remote environments\n" \
    "T - sync single theme\n" \
    "S - skip db connection checking\n" \
    "d - sync database with wp-cli\n" \
    "l - sync languages\n" \
    "m - sync must use plugins\n" \
    "p - sync plugins\n" \
    "t - sync themes\n" \
    "u - sync uploads\n" \
    "\nExample:\n" \
    "du - sync for database and uploads directory\n" \

    read -ep "→ ${bold}Use available option from the list of ${sync_args[$i]}: " cur_flags

    cur_args+=($cur_flags) && clear
  fi
done

# sync environments
FROM=${cur_args[0]}
TO=${cur_args[1]}
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
wip_flag=${cur_args[2]}
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

for ((i=0; i<${#wip_flag}; i++)); do
  # Parse the flags and setup vars
  case "${wip_flag:$i:1}" in
    D)  skip_db="true" && sync_db="true" && read -r -p "$db_message" db_response;; # sync db without connection checking
    P)  sync_dirs+=("plugins"); single_package="true";;                            # sync single plugin
    R)  sync_remote="remote" && read -r -p "$remote_message" response;;            # sync remote environments
    S)  skip_db="true";;                                                           # skip db connection checking
    T)  sync_dirs+=("themes"); single_package="true";;                             # sync single theme
    d)  sync_db="true" && read -r -p "$db_message" db_response;;                   # sync database
    l)  sync_dirs+=("languages");;                                                 # sync languages
    m)  sync_dirs+=("mu-plugins");;                                                # sync must use plugins
    p)  sync_dirs+=("plugins");;                                                   # sync plugins
    t)  sync_dirs+=("themes");;                                                    # sync themes
    u)  sync_dirs+=("uploads");;                                                   # sync uploads
    *)  echo $cur_flags_message && exit 1 ;;
  esac
done



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
    avail=$(wp "@$cur_avail" option get home 2>&1)
  fi
  # message output
  if [[ $avail == *"Error"* ]]; then
    echo "❌  Unable to connect to $cur_avail via wp-cli" && exit 1
  else
    echo "✅  Able to connect to $cur_avail"
  fi
};

[[ -z "$skip_db" ]] && avail_check $FROM
[[ -z "$skip_db" ]] && avail_check $TO

for i in "${!sync_dirs[@]}"; do
  # SSH vars for source/destination environments
  from_ssh="$app_user@$app_ip"
  to_ssh="$app_user_sync@$app_ip_sync"
  # Get current content type path: plugins, uploads etc
  cur_type=${sync_dirs[$i]}
  cur_path="/$cur_type/"
  # Path vars for source environment
  from_env=${app_dir%/}${app_content%/}$cur_path
  #  vars fo vars for destination environment
  to_env=${app_dir_sync%/}${app_content_sync%/}$cur_path
  to_env_def="$to_ssh:${app_dir_sync%/}${app_content_sync%/}$cur_path"
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
    *-local-false-true)        local="true"; from_env="$from_ssh:$from_env";;
    local-*-remote-false)      local="true"; to_env="$to_ssh:$to_env";;
    local-*-remote-true)       local="true"; to_env=$to_env_def;;
    *-local-remote-*)          echo $local_message && exit 1 ;;
    $FROM-$TO-remote-false)    remote="true"; to_env="$from_ssh:$to_env";;
    $FROM-$TO-remote-true)     remote="true"; from_env="$from_env"; to_env="$to_env_def";;
    *)                         echo $cur_env_message && exit 1 ;;
  esac

  # Single sync for Plugins and Themes
  if [[ -n "$single_package" ]]; then
    if [[ "$cur_type" == "plugins" ]]; then
      # get plugins list
      mapfile -t plugins < <( wpi_yq 'plugins.single.[*].name' )
      for p in "${!plugins[@]}"
      do
        echo "[$((p+1))] ${plugins[$p]}"
      done
      read -n 2 -ep "→ ${bold}Choose from $cur_type list for single sync: " cur_p

      # override default from/to path
      from_env="$from_env${plugins[$((cur_p-1))]}/"
      to_env="$to_env${plugins[$((cur_p-1))]}/"
    else
      # choose the theme
      echo "[1] $( wpi_yq 'themes.parent.name' )"
      echo "[2] $( wpi_yq 'themes.child.name' )"
      read -n 1 -ep "→ ${bold}Choose from $cur_type list for single sync: " cur_p
      theme_name=$( wpi_yq 'themes.parent.name' )
      [[ "$cur_p" == "2" ]] && theme_name=$( wpi_yq 'themes.child.name' )

      # override default from/to path
      from_env="$from_env$theme_name/"
      to_env="$to_env$theme_name/"
    fi
  fi
  
  exlude_dirs="--exclude=node_modules --exclude=vendor --exclude=.git --exclude=.idea --exclude=.DS_Store"

  if [[ "$local" == "true" ]]; then
    # Local environment pull/push
    rsync -avz -P --del $exlude_dirs $from_env $to_env
  elif [[ "$remote" == "true" && "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Remote environments sync
    ssh -o ForwardAgent=yes $from_ssh "rsync -aze 'ssh -o StrictHostKeyChecking=no' -P --del $exlude_dirs $from_env $to_env"
  fi
done

if [[ "$db_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  # Export/import database, run search & replace
  wp_flags="--all-tables --quiet"
  wp "@$TO" db export &&
  wp "@$TO" db reset --yes &&
  wp "@$FROM" db export - | wp "@$TO" db import $wp_flags - &&
  echo "🔄 Search replace ${bold}processing..." &&
  wp "@$TO" search-replace "$app_protocol://$app_host" "$app_protocol_sync://$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_protocol:\/\/$app_host" "$app_protocol_sync:\/\/$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_protocol%3A%2F%2F$app_host" "$app_protocol_sync%3A%2F%2F$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_host" "$app_host_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_dir" "$app_dir_sync" $wp_flags &&
  wp "@$TO" search-replace "$app_content" "$app_content_sync" $wp_flags &&
  wp "@$TO" search-replace "@www" "@" $wp_flags &&
  echo "✅  Search replace ${bold}done..."
fi
echo -e "\n\n🔄  Sync from $FROM to $TO complete.\n    ${bold}$TOSITE${normal}\n"
