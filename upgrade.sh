#!/bin/sh
set -eu

# This script is meant for quick & easy upgrade of Funkwhale pods installed via:
#   $ sh -c "$(curl -sSL https://get.funkwhale.audio/upgrade.sh)"
#
# If Ansible step fails with ascii decore error, ensure you have a locale properly set on
# your system e.g apt-get install -y locales locales-all
export LANG="en_US.UTF-8"

funkwhale_version="${1-}"
ansible_flags="${ANSIBLE_FLAGS- --diff}"
skip_confirm="${SKIP_CONFIRM-}"
is_dry_run=${DRY_RUN-false}
base_path="/srv/funkwhale"
ansible_conf_path="$base_path/ansible"
ansible_bin_path="$HOME/.local/bin"
ansible_funkwhale_role_version="${ANSIBLE_FUNKWHALE_ROLE_VERSION-master}"
funkwhale_systemd_after=""
total_steps="4"
latest_version_url="https://docs.funkwhale.audio/latest.txt"
echo
yesno_prompt() {
    local default="${3-}"
    local __resultvar=$1
    local result=""
    local options="yes/no"
    if [ "$default" = "yes" ]; then
        local options="YES/no"
    fi
    if [ "$default" = "no" ]; then
        local options="yes/NO"
    fi
    while true
    do
        read -p "$2 [$options]: " result
        if [ ! -z "$default" ] && [ -z "$result" ]; then
            result="$default"
        fi
        case $result in
            [Yy]* ) result="true"; break;;
            [Nn]* ) result="false"; break;;
            "" ) result="true"; break;;
            *) echo "Please answer [y]es or [n]o";;
        esac
    done
    eval $__resultvar="'$result'"
}

do_upgrade() {
    echo '[Beginning upgrade]'
    playbook_path="$ansible_conf_path/playbook.yml"
    echo "[1/$total_steps] Retrieving currently installed version from $playbook_path"
    current_version=$(grep 'funkwhale_version:' $playbook_path | xargs | sed 's/funkwhale_version: //' | xargs)
    if [ -z $current_version ]; then
        echo "Could not retrieve the current installed version from $playbook_path, the file should exist and contain a 'funkwhale_version:' line"
        exit 1
    fi
    if [ -z "$funkwhale_version" ]; then
        echo "[1/$total_steps] No target version specified, retrieving latest version from $latest_version_url"
        funkwhale_version=$(curl -sfL $latest_version_url || true)
        if [ -z "$funkwhale_version" ]; then
            echo "Could not retrieve latest version, ensure you have network connectivity"
            exit 1
        fi
    fi
    echo
    echo "Upgrade summary:"
    echo
    echo "- Current version: $current_version"
    echo "- Target version: $funkwhale_version"
    if [ "$is_dry_run" = "true" ]; then
        echo "- Running with dry-run mode, your system will be not be modified"
        echo "  Rerun with DRY_RUN=false for a real upgrade."
    else
        echo "- Upgrading may cause temporary downtime on your pod"
    fi;
    echo

    if [ -z "$skip_confirm" ]; then
        yesno_prompt proceed 'Do you want to proceed with the upgrade?' 'yes'
        if [ "$proceed" = "false" ]; then
            echo "Aborting upgrade";
            exit 1;
        fi
    fi
    echo "[2/$total_steps] Replacing current version number in $playbook_path…"
    if [ "$is_dry_run" = "false" ]; then
        sed -i.bak -r "s/(funkwhale_version:)(.*)/\1 $funkwhale_version/" $playbook_path
    fi
    cd "$ansible_conf_path"
    echo "[3/$total_steps] Upgrading ansible dependencies..."
    playbook_command="$ansible_bin_path/ansible-playbook  -i $ansible_conf_path/inventory.ini $ansible_conf_path/playbook.yml -u root $ansible_flags"
    if [ "$is_dry_run" = "true" ]; then
        echo "[3/$total_steps] Skipping playbook because DRY_RUN=true"
    else
        echo "[3/$total_steps] Upgrading Funkwhale using ansible playbook in $ansible_conf_path..."
        $ansible_bin_path/ansible-galaxy install -r requirements.yml -f
        echo "[3/$total_steps] Applying playbook with:"
        echo "  $playbook_command"
        $playbook_command
    fi
    echo "[3/$total_steps] Adding $ansible_conf_path/reconfigure script"
    cat <<EOF >$ansible_conf_path/reconfigure
#!/bin/sh
# reapply playbook with existing parameter
# Useful if you changed some variables in playbook.yml
exec $ansible_bin_path/ansible-playbook  -i $ansible_conf_path/inventory.ini $ansible_conf_path/playbook.yml -u root $ansible_flags
EOF
    chmod +x $ansible_conf_path/reconfigure
    echo
    echo "Upgrade to $funkwhale_version complete!"
    exit
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_upgrade
