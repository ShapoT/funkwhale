# Funkwhale ansible role

An ansible role to install and update [Funkwhale](https://funkwhale.audio).

## Summary

Using this role, you can install and upgrade a Funkwhale pod, closely matching our [standard installation guide](https://docs.funkwhale.audio/installation/debian.html). The role will take care of:

- Installing and configure dependencies and packages
- Install and configure PostgreSQL, Redis and Nginx (optional)
- Install and configure Funkwhale and it's dependencies
- Install and configure a SSL certificate with Let's Encrypt (optional)

## Philosophy

This role strives to:

- Work out-of-the box by default
- Be modular and lightweight
- Avoid dependencies on other ansible roles
- Allow further customization
- Allow running multiple Funkwhale instances on the same host
- Avoid messing with existing software and apps on the server

## Installation and usage

Install ansible:

```
pip3 install --user ansible
```

Create a directory for ansible files:

    mkdir ~/ansible-funkwhale
    cd ansible-funkwhale

Create a playbook requirements and inventory file:

    touch requirements.yml
    touch playbook.yml
    touch inventory.ini
    touch ansible.cfg

Add the following to `requirements.yml`:

```
- src: git+https://dev.funkwhale.audio/funkwhale/ansible
  name: funkwhale
  version: master
```

Install the role:

```
ansible-galaxy install -r requirements.yml
```

Add the following to `ansible.cfg`:

```
[defaults]
# Needed to use become with unprevileged users,
# see https://docs.ansible.com/ansible/latest/user_guide/become.html#becoming-an-unprivileged-user
allow_world_readable_tmpfiles=true
```

Add the following to `playbook.yml`:

```yaml
- hosts: funkwhale-servers
  roles:
    - role: funkwhale
      funkwhale_hostname: yourdomain.funkwhale
      funkwhale_letsencrypt_email: contact@youremail.com
```

See below for a full documentation on available variables.

Add your server to `inventory.ini`:

```ini
[funkwhale-servers]
your-server-ip-or-domain
```

Launch the installation (in check mode, so nothing is applied):

```
ansible-playbook --ask-become-pass -i inventory.ini playbook.yml --check --diff
```

_On some hosts, you may need to install the `python-apt` package for check mode to work_.

This command will show you the changes that would be applied to your system. If you are comfortable with them,
rerun the same command without the `--check` flag.

Once installation is complete, run `/srv/funkwhale/virtualenv/bin/python /srv/funkwhale/api/manage.py createsuperuser` to create your admin account.

## Role Variables

**Required variables**

| name                          | Example                 | Description                                                                                                                          |
| ----------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `funkwhale_hostname`          | `yourdomain.funkwhale`  | The domain name of your Funkwhale pod                                                                                                |
| `funkwhale_letsencrypt_email` | `contact@youremail.com` | The email to associate with your Let's Encrypt certificate (not needed if you set `funkwhale_letsencrypt_enabled: false`, see below) |

**Optional variables**

| name                                  | Default                                                                                                                                                             | Description                                                                                                                                                                             |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `funkwhale_api_ip`                    | `127.0.0.1`                                                                                                                                                         | IP address with which to bind the Funkwhale server                                                                                                                                      |
| `funkwhale_api_port`                  | `5000`                                                                                                                                                              | Port with which to bind the Funkwhale server                                                                                                                                            |
| `funkwhale_config_path`               | `/srv/funkwhale/config`                                                                                                                                             | Path to Funkwhale's configuration directory                                                                                                                                             |
| `funkwhale_nginx_csp_policy`          | `"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; object-src 'none'; media-src 'self' data:"` | Content-Security-Policy header to us. You will need to tweak this if you're serving media files from a separate domain.                                                                 |
| `funkwhale_database_managed`          | `true`                                                                                                                                                              | If `true`, the role will manage the database server and Funkwhale's database                                                                                                            |
| `funkwhale_database_name`             | `funkwhale`                                                                                                                                                         | Name of the Funkwhale database to use                                                                                                                                                   |
| `funkwhale_database_user`             | `funkwhale`                                                                                                                                                         | Postgresql username to login as                                                                                                                                                         |
| `funkwhale_env_vars`                  | `[]`                                                                                                                                                                | List of environment variables to append to the generated `.env` file. Example: `["AWS_ACCESS_KEY_ID=myawsid", "AWS_SECRET_ACCESS_KEY=myawskey"]`                                        |
| `funkwhale_external_storage_enabled`  | `false`                                                                                                                                                             | If `true`, set up the proper configuration to use an external storage for media files                                                                                                   |
| `funkwhale_disable_django_admin`      | `false`                                                                                                                                                             | If `true`, returns a 403 (Forbidden) for `/api/admin`                                                                                                                                   |
| `funkwhale_gunicorn_extra_args`       | `""`                                                                                                                                                                | Additional args to pass to gunicorn in the `funkwhale-server.service` file. Refer to [gunicorn's documentation](https://docs.gunicorn.org/en/stable/settings.html) for possible options |
| `funkwhale_install_path`              | `/srv/funkwhale`                                                                                                                                                    | Path where frontend, api and virtualenv files should be stored (**no trailing slash**)                                                                                                  |
| `funkwhale_letsencrypt_certbot_flags` | `null`                                                                                                                                                              | Additional flags to pass to `certbot`                                                                                                                                                   |
| `funkwhale_letsencrypt_enabled`       | `true`                                                                                                                                                              | If `true`, will configure SSL with certbot and Let's Encrypt                                                                                                                            |
| `funkwhale_media_path`                | `/srv/funkwhale/data/media`                                                                                                                                         | Path where audio and uploaded files should be stored (**no trailing slash**)                                                                                                            |
| `funkwhale_music_path`                | `/srv/funkwhale/data/music`                                                                                                                                         | Path to your existing music library, to use with [CLI import](https://docs.funkwhale.audio/admin/importing-music.html) (**no trailing slash**)                                          |
| `funkwhale_nginx_additional_config`   | `""`                                                                                                                                                                | Additional nginx configuration to add to the Funkwhale `server{}` block                                                                                                                 |
| `funkwhale_nginx_managed`             | `true`                                                                                                                                                              | If `true`, will install and configure nginx                                                                                                                                             |
| `funkwhale_nginx_tls_termination`     | `true`                                                                                                                                                              | If `false`, disable SSL in nginx                                                                                                                                                        |

| `funkwhale_nginx_tls_configure_ciphers` | `true` | Set TLS ciphers, curves, etc, overriding any settings in http{} |
| `funkwhale_nginx_max_body_size` | `100M` | Value of nginx's `max_body_size` parameter to use |
| `funkwhale_protocol` | `https` | If set to `https`, will configure Funkwhale and Nginx to work behind HTTPS. Use `http` to completely disable SSL. |
| `funkwhale_redis_managed` | `true` | If `true`, will install and configure redis |
| `funkwhale_ssl_cert_path` | `` | Path to an existing SSL certificate to use (use in combination with `funkwhale_letsencrypt_enabled: false`) | | `funkwhale_ssl_key_path` |`` | Path to an existing SSL key to use (use in combination with `funkwhale_letsencrypt_enabled: false`) |
| `funkwhale_static_path` | `/srv/funkwhale/data/static` | Path where Funkwhale static files should be stored |
| `funkwhale_systemd_managed` | `true` | If `true`, will configure Funkwhale systemd services |
| `funkwhale_systemd_after` | `redis.service postgresql.service` | Configuration used for Systemd `After=` directive. Modify it if you have a database or redis server on a separate host |
| `funkwhale_systemd_service_name` | `funkwhale` | Name of the generated Systemd service, e.g when calling `systemctl start <xxx>` |
| `funkwhale_username` | `funkwhale` | Username of the system user and owner of Funkwhale data, files and configuration |
| `funkwhale_version` | `latest` | The version to install/upgrade to. You can also use `develop` to run the development branch |
| `funkwhale_custom_pip_packages` | `[]` | A list of additional python packages to download |
| `funkwhale_custom_settings` | `` | Some Python code to append to`api/config/settings/production.py`. Use funkwhale_custom_settings: | ` for multiline code. |

**Installing from source**

If you want to install Funkwhale from source (e.g to try a nonproduction branch, or use your own fork), you use the
following variables:

| name                            | Default                                               | Description                             |
| ------------------------------- | ----------------------------------------------------- | --------------------------------------- |
| `funkwhale_install_from_source` | `false`                                               | Install and build Funkwhale from source |
| `funkwhale_source_url`          | `https://dev.funkwhale.audio/funkwhale/funkwhale.git` | URL to the git repository to use        |

Use the `funkwhale_version` variable to control the git tag/branch to checkout.

## Supported platforms

- Debian 9
- More to come

## Dependencies

This roles has no other dependencies.

## Tests

This role is tested using [molecule](https://molecule.readthedocs.io/en/stable/).
We don't have CI yet, but you can run the tests with `molecule test`.

## Todo

- Backups
- Superuser creation

## License

AGPL3

## Author Information

Contact us at https://funkwhale.audio/community/
