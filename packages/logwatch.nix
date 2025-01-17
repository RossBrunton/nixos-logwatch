{ pkgs, lib, journalCtlEntries ? [], ... }:
let
  mkJournalCtlEntry = { name, title ? null, output ? "cat", unit ? null, script ? null}:
    ''
      echo Adding JournalCtl entry '${name}'
    '' + "echo -e '" + lib.optionalString (title != null) ''
      Title = "${title}"\n
    '' + ''
      LogFile =\nLogFile = logwatch-null\n*JournalCtl = "--output=${output} --unit=${if unit != null then unit else "${name}.service"}"\n' > $out/etc/logwatch/conf/services/${name}.conf
    '' + lib.optionalString (script != null) ''
      cp ${script} $out/etc/logwatch/scripts/services/${name}
    '';
in
pkgs.stdenvNoCC.mkDerivation {
    pname = "logwatch";
    version = "unstable-2024-01-06";

    src = pkgs.fetchgit {
      url = "https://git.code.sf.net/p/logwatch/git";
      rev = "fee92865f3f797ec4a9f07b23c5e737c55139f7d";
      hash = "sha256-nemUvFGpKEoRHelUiHoy0/bkMduj0nZMHEJ1ZP6STCM=";
    };

    nativeBuildInputs = [
      pkgs.makeWrapper
    ];

    patchPhase = ''
      substituteInPlace install_logwatch.sh \
        --replace "/usr/share"      "$out/usr/share"          \
        --replace "/etc/logwatch"   "$out/etc/logwatch"       \
        --replace "/usr/bin/perl"   "${pkgs.perl}/bin/perl"   \
        --replace " perl "          " ${pkgs.perl}/bin/perl " \
        --replace "/usr/sbin"       "$out/bin"                \
        --replace "install -m 0755 -d \$TEMPDIR" ":"
    '';

    buildPhase = "";

    installPhase = ''
      mkdir -p $out/bin
      sh install_logwatch.sh

      # Null log necessary to be able to use journalctl
      echo -e "LogFile = logwatch-null.log" > $out/etc/logwatch/conf/logfiles/logwatch-null.conf

      # Set mailer correctly
      echo -e "mailer = \"${pkgs.postfix}/bin/sendmail -t\"" >> $out/etc/logwatch/conf/logwatch.conf
    '' + (lib.concatMapStrings mkJournalCtlEntry journalCtlEntries);

    postFixup = ''
      substituteInPlace $out/bin/logwatch \
        --replace "/usr/share"    "$out/usr/share"        \
        --replace "/etc/logwatch" "$out/etc/logwatch"     \
        --replace "/usr/bin/perl" "${pkgs.perl}/bin/perl" \
        --replace "/var/cache"    "/tmp"

      substituteInPlace $out/usr/share/logwatch/default.conf/logwatch.conf \
        --replace "/usr/sbin/sendmail"  "${pkgs.postfix}/bin/sendmail" \
        --replace "/var/cache"          "/tmp"

      # Enable runtime stats
      substituteInPlace $out/usr/share/logwatch/default.conf/services/zz-runtime.conf \
        --replace '#$show_uptime = 0' '$show_uptime = 1'

      # Do not show unmatched entries; getting all messages from journalctl unit 'session*' contains a lot more stuff than only sudo
      substituteInPlace $out/usr/share/logwatch/scripts/services/sudo \
        --replace "if (keys %OtherList) {" "if (0) {"

      wrapProgram $out/bin/logwatch \
        --prefix PERL5LIB : "${with pkgs.perlPackages; makePerlPath [ DateManip HTMLParser SysCPU SysMemInfo ]}" \
        --prefix PATH : "${lib.makeBinPath [ pkgs.nettools pkgs.gzip pkgs.bzip2 pkgs.xz ]}" \
        --set pathto_ifconfig  "${pkgs.nettools}/bin/ifconfig"
    '';
  }
