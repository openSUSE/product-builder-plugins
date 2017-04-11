################################################################
# Copyright (c) 2014 SUSE
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file LICENSE); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
################################################################
package KIWIDescrPlugin;

use strict;
use warnings;

use File::Basename;
use base "KIWIBasePlugin";
use Config::IniFiles;
use Data::Dumper;
use Cwd 'abs_path';

sub new {
    # ...
    # Create a new KIWIDescrPlugin object
    # creates patterns file
    # ---
    my $class   = shift;
    my $handler = shift;
    my $config  = shift;
    my $configpath;
    my $configfile;
    my $this = KIWIBasePlugin -> new($handler);
    bless ($this, $class);
    if ($config =~ m{(.*)/([^/]+)$}x) {
        $configpath = $1;
        $configfile = $2;
    }
    if((! $configpath) || (! $configfile)) {
        $this->logMsg("E",
            "wrong parameters in plugin initialisation"
        );
        return;
    }
    my $ini = Config::IniFiles -> new( -file => "$configpath/$configfile" );
    my $name       = $ini->val('base', 'name');
    my $order      = $ini->val('base', 'order');
    my $createrepo = $ini->val('base', 'createrepo');
    my $modifyrepo = $ini->val('base', 'modifyrepo');
    my $rezip      = $ini->val('base', 'rezip');
    my $enable     = $ini->val('base', 'defaultenable');
    # if any of those isn't set, complain!
    if(not defined($name)
        or not defined($order)
        or not defined($createrepo)
        or not defined($rezip)
        or not defined($enable)
    ) {
        $this->logMsg("E",
            "Plugin ini file <$config> seems broken!"
        );
        return;
    }
    $this->name($name);
    $this->order($order);
    $this->{m_createrepo} = $createrepo;
    $this->{m_modifyrepo} = $modifyrepo;
    $this->{m_rezip} = $rezip;
    if($enable != 0) {
        $this->ready(1);
    }
    return $this;
}

sub execute {
    my $this = shift;
    if(not ref($this)) {
        return;
    }
    if($this->{m_ready} == 0) {
        return 0
    }
    my $coll = $this->{m_collect};
    my $basesubdirs = $coll->basesubdirs();
    if(not defined($basesubdirs)) {
        ## prevent crash when dereferencing
        $this->logMsg("E",
            "<basesubdirs> is undefined! Skipping <$this->name()>"
        );
        return 0;
    }
    foreach my $dirlist($this->getSubdirLists()) {
        my ($s,$m) = $this->executeDir(sort @{$dirlist});
    }
    return 0;
}

sub executeDir {
    my @params = @_;
    my $this     = shift @params;
    my @paths    = @params;
    my $call;
    my $status;
    my $cmd;
    if(!@paths) {
        $this->logMsg("W", "Empty path list!");
        return 0;
    }
    my $coll  = $this->{m_collect};
    my $cpeid = $coll->productData()->getInfo("CPEID");
    my $repoid = $coll->productData()->getInfo("REPOID");
    my $metadataonly = $coll->productData()->getVar("RPMHDRS_ONLY");
    my $params = "$this->{m_params} -H" ? $metadataonly eq "true" : "$this->{m_params}";

    my $distroname = $coll->productData()->getInfo("DISTRIBUTION")."."
            . $coll->productData()->getInfo("VERSION");
    my $result = $this -> createRepositoryMetadata(
        \@paths, $repoid, $distroname, $cpeid
    );

    return 1;
}

sub createRepositoryMetadata {
    my @params = @_;
    my $this       = $params[0];
    my $paths      = $params[1];
    my $masterpath = @{$paths}[0];
    my $repoid     = $params[2];
    my $distroname = $params[3];
    my $cpeid      = $params[4];
    my $cmd;
    my $call;
    my $status;
    $cmd = "$this->{m_createrepo}";
    $cmd .= " --unique-md-filenames";
    $cmd .= " --checksum=sha256";
    $cmd .= " --no-database";
    $cmd .= " --repo=\"$repoid\"" if $repoid;
    $cmd .= " --distro=\"$cpeid,$distroname\"" if $cpeid && $distroname;
    if (@{$paths} > 1) {
        $cmd .= " --split";
        $cmd .= " --baseurl=media://";
    }
    foreach my $p (@{$paths}) {
        $cmd .= " $p";
    }
    $this->logMsg("I", "Executing command <$cmd>");
    $call = $this -> callCmd($cmd);
    $status = $call->[0];
    if ($status) {
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("E",
            "Called <$cmd> exit status: <$status> output: $out"
        );
        return 0;
    }
    $cmd = "$this->{m_rezip} $masterpath ";
    $this->logMsg("I", "Executing command <$cmd>");
    $call = $this -> callCmd($cmd);
    $status = $call->[0];
    if($status) {
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("E",
            "Called <$cmd> exit status: <$status> output: $out"
        );
        return 0;
    }

    if (-x "/usr/bin/openSUSE-appstream-process")
    {
        $cmd = "/usr/bin/openSUSE-appstream-process";
        $cmd .= " $masterpath";
        $cmd .= " $masterpath/repodata";

        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("I",
            "Called $cmd exit status: <$status> output: $out"
        );
    }

    if (-e "$masterpath/repodata/repomd.xml") {
      if (-e "$masterpath/license.tar.gz") {
        $cmd = "gzip -d $masterpath/license.tar.gz";
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("I",
            "Called $cmd exit status: <$status> output: $out"
        );
      }
      if (-e "$masterpath/license.tar") {
        $cmd = "$this->{m_modifyrepo}";
        $cmd .= " --unique-md-filenames";
        $cmd .= " --checksum=sha256";
        $cmd .= " $masterpath/license.tar $masterpath/repodata";

        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("I",
            "Called $cmd exit status: <$status> output: $out"
        );
      }

      $cmd = "sign -d $masterpath/repodata/repomd.xml";
      $call = $this -> callCmd($cmd);
      $status = $call->[0];
      my $out = join("\n",@{$call->[1]});
      $this->logMsg("I",
          "Called $cmd exit status: <$status> output: $out"
      );
    }

    return 2;
}

1;
