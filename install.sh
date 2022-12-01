#!/bin/sh
set -eu

# This script is meant for quick & easy install via:
#   $ sh -c "$(curl -sSL https://get.funkwhale.audio/)"
#
# If Ansible step fails with ascii decore error, ensure you have a locale properly set on
# your system e.g apt-get install -y locales locales-all
export LANG="en_US.UTF-8"
funkwhale_version="${FUNKWHALE_VERSION-funkwhale_version_placeholder}"
funkwhale_hostname="${FUNKWHALE_DOMAIN-}"
funkwhale_admin_email="${FUNKWHALE_ADMIN_EMAIL-}"
funkwhale_admin_username="${FUNKWHALE_ADMIN_USERNAME-}"
ansible_flags="${ANSIBLE_FLAGS- --diff}"
ansible_version="${ANSIBLE_VERSION-4.10.0}"
customize_install="${CUSTOMIZE_INSTALL-}"
skip_confirm="${SKIP_CONFIRM-}"
is_dry_run=${DRY_RUN-false}
min_python_version_major="3"
min_python_version_minor="5"
base_path="/srv/funkwhale"
ansible_conf_path="$base_path/ansible"
ansible_bin_path="$HOME/.local/bin"
ansible_funkwhale_role_version="${ANSIBLE_FUNKWHALE_ROLE_VERSION-master}"
ansible_funkwhale_role_path="${ANSIBLE_FUNKWHALE_ROLE_PATH-}"
funkwhale_systemd_after=""
total_steps="4"

echo
setup() {

    if [ "$funkwhale_version" = 'funkwhale_version_placeholder' ]; then
        echo "No FUNKWHALE_VERSION found and the script didn't include a default one."
        echo "Relaunch the script with FUNKWHALE_VERSION=yourdesiredversion"
        exit 1
    fi


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

    echo
    if [ -z "$funkwhale_hostname" ]; then
        read -p "Enter your desired Funkwhale domain (e.g funkwhale.example): "  funkwhale_hostname
    fi
    if [ -z "$funkwhale_admin_username" ]; then
        read -p "Enter the username for the admin account (leave empty to skip account creation) "  funkwhale_admin_username
    fi
    if [ -z "$funkwhale_admin_email" ]; then
        read -p "Enter the email used for the admin user (and Let's Encrypt certificate): "  funkwhale_admin_email
    fi
    if [ -z "$customize_install" ]; then
        yesno_prompt customize_install "The complete installation will setup Nginx, Certbot, PostgresQL and Redis. Do you want customize what is installed?" "no"
    fi

    if [ "$customize_install" = "true" ]; then
        yesno_prompt funkwhale_nginx_managed 'Install and manage Nginx and Certbot?' 'yes'
        yesno_prompt funkwhale_database_managed 'Install and manage PostgreSQL?' 'yes'
        if [ "$funkwhale_database_managed" = "false" ]; then
            read -p "Enter your database configuration, (e.g postgresql://user@localhost:5432/database_name): "  funkwhale_database_url
            funkwhale_systemd_after="funkwhale_systemd_after: "
        fi
        yesno_prompt funkwhale_redis_managed 'Install and manage Redis?' 'yes'
        if [ "$funkwhale_redis_managed" = "false" ]; then
            read -p "Enter your redis configuration, (e.g redis://127.0.0.1:6379/0): "  funkwhale_redis_url
            funkwhale_systemd_after="funkwhale_systemd_after: "
        fi
        yesno_prompt funkwhale_systemd_managed 'Install and manage systemd services files?' 'yes'
        yesno_prompt funkwhale_disable_django_admin 'Disable access to API admin dashboard?' 'no'
    else
        funkwhale_nginx_managed="true"
        funkwhale_database_managed="true"
        funkwhale_redis_managed="true"
        funkwhale_disable_django_admin="false"
        funkwhale_systemd_managed="true"
    fi


    echo
    echo "Installation summary:"
    echo
    echo "- version: $funkwhale_version"
    echo "- domain: $funkwhale_hostname"
    echo "- Admin username: $funkwhale_admin_username"
    echo "- Admin email: $funkwhale_admin_email"
    echo "- Manage nginx and certbot: $funkwhale_nginx_managed"
    echo "- Manage redis: $funkwhale_redis_managed"
    echo "- Manage systemd unit files: $funkwhale_systemd_managed"
    if [ "$funkwhale_redis_managed" = "false" ]; then
        echo "  - Custom redis configuration: $funkwhale_redis_url"
    fi
    echo "- Manage PostgreSQL: $funkwhale_database_managed"
    if [ "$funkwhale_database_managed" = "false" ]; then
        echo "  - Custom PostgreSQL configuration: $funkwhale_database_url"
    fi
    if [ "$funkwhale_disable_django_admin" = "true" ]; then
        echo "- Disabled access to API admin dashboard"
    fi

    if [ "$is_dry_run" = "true" ]; then
        echo "Running with dry-run mode, your system will be not be modified (apart from Ansible installation)."
        echo "Rerun with DRY_RUN=false for a real install."
    fi;
    echo
    if [ -z "$skip_confirm" ]; then
        yesno_prompt proceed 'Do you want to proceed with the installation?' 'yes'
        case $proceed in
            [Nn]* ) echo "Aborting script."; exit 1;;
            *) echo "Please answer yes or no";;
        esac
    fi

}

semver_parse() {
	major="${1%%.*}"
	minor="${1#$major.}"
	minor="${minor%%.*}"
	patch="${1#$major.$minor.}"
	patch="${patch%%[-.]*}"
}

get_python_version () {
    python_version=""
    if [ -x "$(command -v python3)" ]; then
        python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
    fi
}
has_sufficient_python_version() {
    python_ok=""
    semver_parse "$1"
    if [ "$major" -ge "$min_python_version_major" ] && [ "$minor" -ge "$min_python_version_minor" ]; then
        python_ok="true"
    fi
}
install_packages() {
    package_manager="apt-get"
    if [ "$package_manager" = 'apt-get' ]; then
        $package_manager update
        $package_manager install -y "$@"
    fi
}

do_install() {
    setup
    echo '[Beginning installation]'
    echo "[1/$total_steps] Checking python3 version"
    get_python_version
    should_install_python="1"
    if [ ! -z "$python_version" ]; then
        has_sufficient_python_version "$python_version"
        if [ ! -z "$python_ok" ]; then
            echo "[1/$total_steps] $python_version with sufficient version found, skipping"
            should_install_python="0"
        fi
    fi
    if [ -z "$python_version" ]; then
        echo "[1/$total_steps] Python3 not found, installing"
        install_packages python3 python3-pip

    elif [ "$should_install_python" -eq "1" ]; then
        echo "[1/$total_steps] Python $python_version found, $min_python_version_major.$min_python_version_minor needed, upgrading"
        install_packages python3 python3-pip
    else
        echo "[1/$total_steps] Found Python $python_version, skipping upgrade"
    fi
    init_ansible
    if [ "$is_dry_run" = "false" ]; then
        run_playbook
        configure_server
    fi
    if [ "$is_dry_run" = "true" ]; then
        echo "Rerun with DRY_RUN=false for a real install."
    else
        echo "Done!"
        echo " - Everything was installed in the $base_path directory"
        if [ ! -z "$funkwhale_admin_username" ]; then
            echo " - Created a superuser account with username $funkwhale_admin_username and the password you supplied"
        fi
        if [ "$funkwhale_nginx_managed" = "true" ]; then
            echo " - Your Funkwhale server is now up and running at https://$funkwhale_hostname"
        else
            echo " - To complete the installation, you need to setup an Nginx or Apache2 reverse proxy: https://docs.funkwhale.audio/installation/index.html#reverse-proxy"
        fi

        echo " - You can run management commands by calling $base_path/manage, e.g $base_path/manage import_files"
        echo " - Edit your pod configuration in $ansible_conf_path/playbook.yml and apply the changes with: sudo $ansible_conf_path/reconfigure"
        echo ' - To upgrade to the latest version, run: sudo sh -c "$(curl -sSL https://get.funkwhale.audio/upgrade.sh)"'
    fi

}

init_ansible() {
    echo "[2/$total_steps] Installing ansible dependencies..."
    install_packages  curl git python3-pip python3-apt python3-psycopg2 sudo locales locales-all
    echo "[2/$total_steps] Installing Ansible..."
    pip3 install --user ansible=="$ansible_version"

    echo "[2/$total_steps] Creating ansible configuration files in $ansible_conf_path..."
    mkdir -p "$ansible_conf_path"
    cd "$ansible_conf_path"
    cat <<EOF >ansible.cfg
[defaults]
# Needed to use become with unprevileged users,
# see https://docs.ansible.com/ansible/latest/user_guide/become.html#becoming-an-unprivileged-user
#allow_world_readable_tmpfiles=true
EOF
    if [ "$ansible_funkwhale_role_path" = '' ]; then
    cat <<EOF >requirements.yml
- src: git+https://dev.funkwhale.audio/funkwhale/ansible
  name: funkwhale
  version: $ansible_funkwhale_role_version
EOF
    else
        mkdir -p "$ansible_conf_path/roles"
        echo "roles_path = $ansible_conf_path/roles" >> ansible.cfg
        echo "Symlinking local version of the ansible role: $ansible_funkwhale_role_path to $ansible_conf_path/roles/funkwhale"
        rm -f "$ansible_conf_path/roles/funkwhale"
        ln -s "$ansible_funkwhale_role_path" "$ansible_conf_path/roles/funkwhale"
    fi
    cat <<EOF >playbook.yml
- hosts: funkwhale_servers
  roles:
    - role: funkwhale
      funkwhale_hostname: $funkwhale_hostname
      funkwhale_version: $funkwhale_version
      funkwhale_letsencrypt_email: $funkwhale_admin_email
      # Add any environment variables to the generated .env by uncommenting and editing the lines below
      # then execute ./reconfigure
      # funkwhale_env_vars:
      #   - "EMAIL_CONFIG=smtp+tls://user@:password@youremail.host:587"
      #   - "MYCUSTOM_ENV_VAR=test"
EOF
    if [ "$funkwhale_nginx_managed" = "false" ]; then
      cat <<EOF >>playbook.yml
      funkwhale_nginx_managed: false
EOF
    fi
    if [ "$funkwhale_database_managed" = "false" ]; then
      cat <<EOF >>playbook.yml
      funkwhale_database_managed: false
      funkwhale_database_url: $funkwhale_database_url
EOF
    fi
    if [ "$funkwhale_redis_managed" = "false" ]; then
      cat <<EOF >>playbook.yml
      funkwhale_redis_managed: false
      funkwhale_redis_url: $funkwhale_redis_url
EOF
    fi
    if [ "$funkwhale_systemd_managed" = "false" ]; then
      cat <<EOF >>playbook.yml
      funkwhale_systemd_managed: false
EOF
    fi
		if [ "$(lsb_release -sc)" = "focal" ]; then
			cat <<EOF >>playbook.yml
      funkwhale_custom_pip_packages:
        - twisted==22.4.0
EOF
		fi
    cat <<EOF >reconfigure
#!/bin/sh
# reapply playbook with existing parameter
# Useful if you changed some variables in playbook.yml
exec $ansible_bin_path/ansible-playbook  -i $ansible_conf_path/inventory.ini $ansible_conf_path/playbook.yml -u root $ansible_flags
EOF
    chmod +x ./reconfigure
    if [ "$funkwhale_redis_managed" = "false" ]; then
        cat <<EOF >>playbook.yml
      funkwhale_redis_url: $funkwhale_redis_url
EOF
    fi
    if [ ! -z "$funkwhale_systemd_after" ]; then
        cat <<EOF >>playbook.yml
      $funkwhale_systemd_after
EOF
    fi
    cat <<EOF >inventory.ini
[funkwhale_servers]
127.0.0.1 ansible_connection=local ansible_python_interpreter=/usr/bin/python3
EOF
    if [ "$ansible_funkwhale_role_path" = '' ]; then
        echo "[2/$total_steps] Downloading Funkwhale playbook dependencies"
        $ansible_bin_path/ansible-galaxy install -r requirements.yml -f
    else
        echo "[2/$total_steps] Skipping playbook dependencies, using local role instead"
    fi
}
run_playbook() {
    cd "$ansible_conf_path"
    echo "[3/$total_steps] Installing Funkwhale using ansible playbook in $ansible_conf_path..."
    playbook_command="$ansible_bin_path/ansible-playbook  -i $ansible_conf_path/inventory.ini $ansible_conf_path/playbook.yml -u root $ansible_flags"
    if [ "$is_dry_run" = "true" ]; then
        playbook_command="$playbook_command --check"
        echo "[3/$total_steps] Skipping playbook because DRY_RUN=true"
        return 0
    fi

    echo "[3/$total_steps] Applying playbook with:"
    echo "  $playbook_command"
    $playbook_command
}

configure_server() {
    echo "[4/$total_steps] Running final server configuration…"
    echo "[4/$total_steps] Creating simple management script at $base_path/manage"
    cat <<EOF >$base_path/manage
#!/bin/sh
set -eu
sudo -u funkwhale -E $base_path/virtualenv/bin/python $base_path/api/manage.py \$@
EOF
    chmod +x $base_path/manage
    if [ -z "$funkwhale_admin_username" ]; then
        echo "[4/$total_steps] Skipping superuser account creation"
    else
        echo "[4/$total_steps] Creating superuser account…"
        echo "  Please input the password for the admin account password"
        LOGLEVEL=error sudo -u funkwhale -E $base_path/virtualenv/bin/python \
            $base_path/api/manage.py createsuperuser \
            --email $funkwhale_admin_email \
            --username $funkwhale_admin_username \
            -v 0
    fi
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_install
