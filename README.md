# WPI Sync

Syncing WPI Bedrock-based WordPress environments with WP-CLI aliases and `rsync`.

## Installation

Download `sync.sh` script in your WPI Bedrock directory and place inside of there.

Make sure that `sync.sh` is executable (`chmod u+x sync.sh`).

## Configuration

Edit the variables at the WPI env.yml to match the settings for your environments:

* `app_host` — App host/domain
* `app_user` — App user
* `app_ip` — App IP
* `app_dir` — Path to current app webroot directory
* `app_content` — Path to WordPress content directory of current environment
* `app_protocol` — App protocol http or https
* `db_name` — App database name
* `db_user` — App database user
* `db_pass` — App database password

### WP-CLI aliases

WP-CLI aliases will be created automatically in order for the sync script to work on the WPI project init.
Open `wp-cli.yml` and check the aliases before running the sync.

#### Example for WP-CLI aliases

```yml
path: web/wp
server:
  docroot: web

@local:
   ssh: vagrant@127.0.0.1:/home/vagrant/apps/wpi.test/htdocs

@dev:
   ssh: wpi@1.1.1.1:/home/wpi/webapps/wpi/live

@staging:
   ssh: wpi@1.1.1.1:/home/wpi/webapps/wpi/live

@prod:
   ssh: wpi@1.1.1.1:/home/wpi/webapps/wpi/live
```

Test the aliases to make sure they're working:

```sh
$ wp @development
$ wp @staging
$ wp @production
```

When you sync down to your local development environment a database backup is performed with `wp db export`.
This helps you safely recover your database if you accidentally sync.

### Telegram notification

♨️ In progress

## Usage

Some possible sync commands:

```sh
#  Full push from local to staging
$ ./sync.sh local staging -duptlm

#  Push only database and uploads directory from local to staging
$ ./sync.sh local staging -du

#  Pull only database and uploads directory from staging to local
$ ./sync.sh staging local -du

#  Push only plugins directory from local to staging
$ ./sync.sh local staging -p

#  Full push from local to prod with protection flag 'R'
$ ./sync.sh local prod -duptlmR

#  Full sybc from prod to staging with protection flag 'R'
$ ./sync.sh prod staging -duptlmR
```

Available flags:

```
R - sync remote environments
d - sync database
l - sync languages
m - sync must use plugins
p - sync plugins
t - sync themes
u - sync uploads
```

## Troubleshooting and support

send us the [email](mailto:dev@wpi.pw) or leave the issue
