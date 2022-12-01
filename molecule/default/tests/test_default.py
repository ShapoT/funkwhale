import json
import os
import pytest
import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ["MOLECULE_INVENTORY_FILE"]
).get_hosts("all")


@pytest.mark.parametrize("service", ["redis-server", "postgresql", "nginx"])
def test_installed_services(host, service):
    service = host.service(service)
    assert service.is_running
    assert service.is_enabled


def test_database_created(host):
    cmd = """
        sudo -u postgres psql -A -t -c \
            "SELECT 1 FROM pg_catalog.pg_user u WHERE u.usename =  'funkwhale';"
    """
    result = host.run(cmd)
    assert result.stdout == "1"


def test_database_user_created(host):
    cmd = """
        sudo -u postgres psql -A -t -c "SELECT 1 FROM pg_database WHERE datname = 'funkwhale';"
    """
    result = host.run(cmd)
    assert result.stdout == "1"


def test_funkwhale_user_creation(host):
    user = host.user("funkwhale")
    assert user.home == "/srv/funkwhale"
    assert user.shell == "/bin/false"


@pytest.mark.parametrize(
    "path",
    [
        "/srv/funkwhale/",
        "/srv/funkwhale/data/media",
        "/srv/funkwhale/data/static",
        "/srv/funkwhale/data/music",
    ],
)
def test_funkwhale_directories_creation(path, host):
    dir = host.file(path)

    assert dir.exists is True
    assert dir.is_directory is True


def test_funkwhale_env_file(host):
    secret_key = host.file("/srv/funkwhale/config/django_secret_key").content.decode()
    assert len(secret_key) > 0
    f = host.file("/srv/funkwhale/config/.env")
    env_content = f.content.decode()
    assert "MEDIA_ROOT=/srv/funkwhale/data/media" in env_content
    assert "STATIC_ROOT=/srv/funkwhale/data/static" in env_content
    assert "MUSIC_DIRECTORY_PATH=/srv/funkwhale/data/music" in env_content
    assert "MUSIC_DIRECTORY_SERVE_PATH=/srv/funkwhale/data/music" in env_content
    assert "FUNKWHALE_HOSTNAME=yourdomain.funkwhale" in env_content
    assert "FUNKWHALE_PROTOCOL=https" in env_content
    assert "DJANGO_SECRET_KEY={}".format(secret_key) in env_content
    assert "FUNKWHALE_API_IP=127.0.0.1" in env_content
    assert "FUNKWHALE_API_PORT=5000" in env_content
    assert "REVERSE_PROXY_TYPE=nginx" in env_content
    assert "DATABASE_URL=postgresql://funkwhale@:5432/funkwhale" in env_content
    assert "CACHE_URL=redis://127.0.0.1:6379/0" in env_content
    assert "EMAIL_CONFIG=smtp+tls://user@:password@youremail.host:587" in env_content
    assert "DEFAULT_FROM_EMAIL=noreply@yourdomain" in env_content
    assert "FUNKWHALE_FRONTEND_PATH=/srv/funkwhale/front/dist" in env_content
    assert "FUNKWHALE_SPA_HTML_ROOT=/srv/funkwhale/front/dist/index.html" in env_content
    assert "NGINX_MAX_BODY_SIZE=100M" in env_content
    assert "DJANGO_SETTINGS_MODULE=config.settings.production" in env_content

    # additional vars
    assert "ADDITIONAL_VAR=1" in env_content
    assert "ADDITIONAL_VAR=2" in env_content


def test_frontend_download(host):
    f = host.file("/srv/funkwhale/front/dist/index.html")

    assert f.exists is True


def test_api_download(host):
    f = host.file("/srv/funkwhale/api/funkwhale_api/__init__.py")

    assert f.exists is True
    assert f.contains('__version__ = "0.19.0-rc2"') is True


def test_virtualenv(host):
    expected_packages = {"Django", "djangorestframework", "celery"}
    packages = host.pip_package.get_packages(
        pip_path="/srv/funkwhale/virtualenv/bin/pip"
    )
    names = set(packages.keys())

    intersection = expected_packages & names
    assert intersection == expected_packages


def test_static_files_copied(host):
    f = host.file("/srv/funkwhale/data/static/admin/css/base.css")

    assert f.exists is True


def test_migrations_applied(host):
    cmd = """
        sudo -u postgres psql funkwhale -A -t -c "SELECT 1 from django_migrations where app = 'music' and name = '0039_auto_20190423_0820';"
    """
    result = host.run(cmd)
    assert result.stdout == "1"


@pytest.mark.parametrize(
    "service",
    ["funkwhale-server", "funkwhale-worker", "funkwhale-beat", "funkwhale.target"],
)
def test_funkwhale_services(service, host):
    service = host.service(service)
    assert service.is_running
    assert service.is_enabled


def test_certbot_auto_installed(host):
    assert host.find_command("certbot-auto") == "/usr/local/bin/certbot-auto"


def test_nginx_configuration(host):
    f = host.file("/etc/nginx/sites-enabled/yourdomain.funkwhale.conf")
    assert f.exists is True
    content = f.content.decode()
    assert "ssl_certificate /certs/test.crt;" in content
    assert "ssl_certificate_key /certs/test.key;" in content


def test_e2e_front(host):
    command = 'curl -k https://localhost --header "Host: yourdomain.funkwhale"'
    result = host.run(command)
    assert '<meta content="Funkwhale" property="og:site_name" />' in result.stdout


def test_e2e_api(host):
    command = 'curl -k https://localhost/api/v1/instance/nodeinfo/2.0/ --header "Host: yourdomain.funkwhale"'
    payload = host.run(command).stdout
    data = json.loads(payload)
    assert data["software"]["version"] == "0.19.0-rc2"
