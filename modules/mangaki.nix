{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.mangaki;
  pcfg = config.services.postgresql;

  mangakiDir = pkgs.mangaki + "/" + pkgs.mangaki.python.sitePackages;
  # Why is it so hard to get dev-dependencies whilst including the project...
  mangakiEnv = pkgs.mangaki.python.withPackages (_: [ pkgs.mangaki ] ++ pkgs.mangaki-env.poetryPackages);

  configSource = with generators; toINI {
    mkKeyValue = mkKeyValueDefault {
      # Not sure if this is a strict requirement but the default config come with true/false like this
      mkValueString = v:
        if true == v then "True"
        else if false == v then "False"
        else mkValueStringDefault {} v;
    } "=";
  } cfg.settings;
  configFile = pkgs.writeText "settings.ini" configSource;
in
{
  options.services.mangaki = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable the Mangaki service
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Mangaki configuration
      '';
    };
  };

  config = mkIf cfg.enable {
    services.redis.enable = true;

    services.postgresql.enable = true;
    services.postgresql.ensureDatabases = [ "mangaki" ];
    services.postgresql.ensureUsers = [
      {
        name = "mangaki";
        ensurePermissions = { "DATABASE mangaki" = "ALL PRIVILEGES"; };
      }
    ];

    systemd.services.mangaki = {
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      description = "Mangaki service";
      path = [ mangakiEnv ];
      environment.MANGAKI_SETTINGS_PATH = configFile;

      serviceConfig = {
        User = "mangaki";
        Group = "mangaki";
        PermissionsStartOnly = true;

        StateDirectory = "mangaki";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/mangaki";
      };

      preStart = ''
        # Create required exists if they don't exist
        ${pkgs.sudo}/bin/sudo -u ${pcfg.superUser} ${pcfg.package}/bin/psql \
          -d mangaki -c \
          "create extension if not exists pg_trgm; \
           create extension if not exists unaccent"
      '';

      script = ''
        python ${mangakiDir}/mangaki/manage.py migrate
        python ${mangakiDir}/mangaki/manage.py runserver
      '';
    };

    systemd.services.mangaki-worker = {
      after = [ "mangaki.service" ];
      requires = [ "mangaki.service" ];
      wantedBy = [ "multi-user.target" ];

      description = "Mangaki background tasks runner";
      path = [ mangakiEnv ];
      environment.MANGAKI_SETTINGS_PATH = configFile;

      serviceConfig = {
        User = "mangaki";
        Group = "mangaki";
        WorkingDirectory = mangakiDir + "/mangaki";
      };

      script = ''
        celery -B -A mangaki:celery_app worker -l INFO
      '';
    };

    users = {
      users.mangaki = {
        group = "mangaki";
        description = "Mangaki user";
      };

      groups.mangaki = { };
    };

    services.mangaki.settings =
      let
        mkDefaultRecFunc = (_: v: if isAttrs v
          then mkDefaultRec v
          else mkDefault v);
        mkDefaultRec = mapAttrs mkDefaultRecFunc; # broken with toINI
      in
      {

        debug = {
          DEBUG = true;
          # Debug JavaScript frontend
          DEBUG_VUE_JS = true;
        };

        email.EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend";

        secrets = {
          # Choose your own password or generate it with `pwgen -s -c 60 1`
          SECRET_KEY = "CHANGE_ME";
          # DB_PASSWORD = "YOUR_POSTGRE_PASSWORD";
          # MAL_PASS = "";
        };

        # deployment = {
        #   MEDIA_ROOT = "<base directory for media files>";
        #   STATIC_ROOT = "<base directory for static files>";
        #   DATA_ROOT = "<base directory for data files: snapshots of algorithms, side information>";
        # };

        # hosts.ALLOWED_HOSTS = "<see https://docs.djangoproject.com/fr/1.10/ref/settings/#allowed-hosts>";

        # # Used to get posters and user lists
        # mal = {
        #   MAL_USER = "";
        #   MAL_USER_AGENT = "";
        # };

        # anidb = {
        #   ANIDB_CLIENT = "";
        #   ANIDB_VERSION = 1;
        # };

        # pgsql = {
        #   DB_HOST = "<defaults to 127.0.0.1>";
        #   DB_NAME = "<defaults to mangaki>";
        #   DB_USER = "<defaults to django>";
        # };

        # # (not required, only if you want to enable Sentry support)
        # sentry.DSN = "<sentry DSN>";

        # smtp = {
        #   EMAIL_HOST = "";
        #   EMAIL_HOST_PASSWORD = "";
        #   EMAIL_HOST_USER = "";
        #   EMAIL_PORT = "";
        #   EMAIL_SSL_CERTFILE = "";
        #   EMAIL_SSL_KEYFILE = "";
        #   EMAIL_TIMEOUT = "";
        #   EMAIL_USE_SSL = "";
        #   EMAIL_USE_TLS = "";
        # };

      };
  };
}
