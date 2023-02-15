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
        $this->logMsg("E", "wrong parameters in plugin initialisation");
        return 1;
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
        $this->logMsg("E", "Plugin ini file <$config> seems broken!");
        return 1;
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
        $this->logMsg("E", "<basesubdirs> is undefined! Skipping <$this->name()>");
        return 1;
    }
    foreach my $dirlist($this->getSubdirLists()) {
        $this->executeDir(sort @{$dirlist});
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
    my $repoids = $coll->productData()->getInfo("REPOID");
    my $distroname = $coll->productData()->getInfo("DISTRO");
    my $result = $this -> createRepositoryMetadata(
        \@paths, $repoids, $distroname
    );

    return 0;
}

sub addLicenseFile {
    my @params = @_;
    my $this        = $params[0];
    my $masterpath  = $params[1];
    my $licensename = $params[2];

    my $call;
    my $cmd;
    my $status;

    if (-e "$masterpath/$licensename.tar.gz") {
      $cmd = "gzip -d $masterpath/$licensename.tar.gz";

      $call = $this -> callCmd($cmd);
      $status = $call->[0];
      my $out = join("\n",@{$call->[1]});
      $this->logMsg("I",
          "Called $cmd exit status: <$status> output: $out"
      );
    }
    if (-e "$masterpath/$licensename.tar") {
      my $external_license_dir = $masterpath.".license";
      $this->logMsg("I", "Extracting license.tar");
      if (system("mkdir -p $external_license_dir")) {
          $this->logMsg( "E", "mkdir failed!");
          return 1;
      }
      system("tar xf $masterpath/$licensename.tar -C $external_license_dir");
      my $result = $? >> 8;
      if ($result != 0) {
          $this->logMsg( "E", "Untar failed!");
          return 1;
      }
      if ( ! -e "$external_license_dir/license.txt" ) {
          $this->logMsg( "E", "No license.txt extracted!");
          return 1;
      }

      $cmd = "$this->{m_modifyrepo}";
      $cmd .= " --unique-md-filenames";
      $cmd .= " --checksum=sha512";
      $cmd .= " $masterpath/$licensename.tar $masterpath/repodata";

      $call = $this -> callCmd($cmd);
      $status = $call->[0];
      my $out = join("\n",@{$call->[1]});
      $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
      unlink "$masterpath/$licensename.tar";
    }
}

sub createRepositoryMetadata {
    my @params = @_;
    my $this       = $params[0];
    my $paths      = $params[1];
    my $masterpath = @{$paths}[0];
    my $repoids    = $params[2];
    my $distroname = $params[3];
    my $cmd;
    my $call;
    my $status;
    my $coll = $this->{m_collect};

    $cmd = "$this->{m_createrepo}";
    $cmd .= " --unique-md-filenames";
    # the glob is only matching on files, so we need it for every directory depth
    $cmd .= " --excludes=boot/*.rpm";
    $cmd .= " --excludes=boot/*/*.rpm";
    $cmd .= " --checksum=sha512";
    $cmd .= " --no-database";
    $cmd .= " --error-exit-val"; # is not working with old createrepo
    foreach my $repoid (split(/\s+/, $repoids)) {
        $cmd .= " --repo=\"$repoid\"";
    }
    $cmd .= " --distro=\"$distroname\"" if $distroname;
    if (@{$paths} > 1) {
        $cmd .= " --split";
        $cmd .= " --baseurl=media://";
    }

    ### set repository tags
    my $debugmedium  = $this->{m_collect}->productData()->getOpt("DEBUGMEDIUM");
    my $sourcemedium = $this->{m_collect}->productData()->getOpt("SOURCEMEDIUM");
    foreach my $p (@{$paths}) {
        $cmd .= " --content=\"debug\"" if $debugmedium && $p =~ m{.*$debugmedium$}x;
        $cmd .= " --content=\"source\"" if $sourcemedium && $p =~ m{.*$sourcemedium$}x;
    }
    my $flavor = $this->{m_collect}->productData()->getVar("FLAVOR");
    $cmd .= " --content=\"pool\"" if $flavor =~ m{ftp}i || $flavor =~ m{pool}i;

    foreach my $p (@{$paths}) {
        $cmd .= " $p";
    }
    $cmd .= " 2>&1"; # verbose output
    $this->logMsg("I", "Executing command <$cmd>");
    $call = $this -> callCmd($cmd);
    $status = $call->[0];
    if ($status) {
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("E", "Called <$cmd> exit status: <$status> output: $out");
        return 1;
    }
    $cmd = "$this->{m_rezip} $masterpath ";
    $this->logMsg("I", "Executing command <$cmd>");
    $call = $this -> callCmd($cmd);
    $status = $call->[0];
    if($status) {
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("E", "Called <$cmd> exit status: <$status> output: $out");
        return 1;
    }

    if (-x "/usr/bin/openSUSE-appstream-process")
    {
        $cmd = "/usr/bin/openSUSE-appstream-process";
        $cmd .= " $masterpath";
        $cmd .= " $masterpath/repodata";

        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
    }

    if ( -f "/usr/bin/add_product_susedata" ) {
        my $kwdfile = abs_path(
            $this->collect()->{m_xml}->{xmlOrigFile}
        );
        $kwdfile =~ s/\.(?:kiwi|xml)$/.kwd/;
        $cmd = "/usr/bin/add_product_susedata";
        $cmd .= " -u"; # unique filenames
        $cmd .= " -g"; # add gpg key ids as tags
        $cmd .= " -k $kwdfile";
        $cmd .= " -p"; # add diskusage data
        $cmd .= " -e /usr/share/doc/packages/eulas";
        $cmd .= " -d $masterpath";
        $this->logMsg("I", "Executing command <$cmd>");
        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        if($status) {
            my $out = join("\n",@{$call->[1]});
            $this->logMsg("E", "Called <$cmd> exit status: <$status> output: $out");
            return 1;
        }
    }

    if (-e "$masterpath/repodata/repomd.xml") {

      $this->addLicenseFile($masterpath, "license");
      foreach my $product (@{$coll->{m_products}}) {
        $this->logMsg("I", "Check for $product license file");
        $this->addLicenseFile($masterpath, "license-$product");
      }

      # rpm-md modulemd files
      if (-e "/usr/src/packages/SOURCES/repos/_modulemd.yaml") {
         $cmd = "/usr/lib/build/writemodulemd --filter /usr/src/packages/SOURCES/repos/_modulemd.yaml $masterpath/repodata > $masterpath/repodata/modules.yaml";
         $call = $this -> callCmd($cmd);
         $status = $call->[0];
         my $out = join("\n",@{$call->[2]});
         $this->logMsg("I",
             "Called $cmd exit status: <$status> output: $out"
         );
         return 1 if $status;
         if (-s "$masterpath/repodata/modules.yaml") {
             $cmd = "/usr/bin/modifyrepo $masterpath/repodata/modules.yaml $masterpath/repodata/";
             $call = $this -> callCmd($cmd);
             $status = $call->[0];
             $out = join("\n",@{$call->[2]});
             $this->logMsg("I",
                 "Called $cmd exit status: <$status> output: $out"
             );
             return 1 if $status;
         }
         unlink("$masterpath/repodata/modules.yaml");
      }

      # comps files from metapackages
      #
      my $out;
      if (-d "$masterpath/comps") {
         opendir(DH, "$masterpath/comps");
         foreach my $comps (readdir(DH)) {
           next if $comps =~ /^\./m;
           # decompress file
           if ($comps =~ /\.gz$/m) {
               $cmd = "gunzip $masterpath/comps/$comps";
               $call = $this -> callCmd($cmd);
               $status = $call->[0];
               $out = join("\n",@{$call->[2]});
               $this->logMsg("I",
                   "Called $cmd exit status: <$status> output: $out"
               );
               return 1 if $status;
               $comps =~ s/\.gz$//;
           }

           # add uncompressed file
           $cmd = "/usr/bin/modifyrepo --no-compress --mdtype=group $masterpath/comps/$comps $masterpath/repodata/";
           $call = $this -> callCmd($cmd);
           $status = $call->[0];
           $out = join("\n",@{$call->[2]});
           $this->logMsg("I",
               "Called $cmd exit status: <$status> output: $out"
           );
           return 1 if $status;

           # add compressed file
           $cmd = "/usr/bin/modifyrepo --compress-type=xz --mdtype=group_xz $masterpath/comps/$comps $masterpath/repodata/";
           $call = $this -> callCmd($cmd);
           $status = $call->[0];
           $out = join("\n",@{$call->[2]});
           $this->logMsg("I",
               "Called $cmd exit status: <$status> output: $out"
           );
           return 1 if $status;

           unlink("$masterpath/comps/$comps");
         }
         closedir(DH);
         rmdir("$masterpath/comps");
      }

      # detached signature
      $cmd = "sign -d $masterpath/repodata/repomd.xml";
      $call = $this -> callCmd($cmd);
      $status = $call->[0];
      $out = join("\n",@{$call->[1]});
      $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
      return 1 if $status;

      # detached pubkey
      $cmd = "sign -p $masterpath/repodata/repomd.xml > $masterpath/repodata/repomd.xml.key";
      $call = $this -> callCmd($cmd);
      $status = $call->[0];
      $out = join("\n",@{$call->[1]});
      $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
      return 1 if $status;

      # create SBOM data, if the build tool is available
      if (-x "/usr/lib/build/generate_sbom") {
	# SPDX
        my $spdx_distro = $this->collect()->productData()->getInfo("PURL_DISTRO");
	if (!$spdx_distro) {
          # some guessing for our old distros to avoid further changes there
          my $vendor = $this->collect()->productData()->getInfo("VENDOR");
          my $distname = $this->collect()->productData()->getVar("DISTNAME");
          my $version = $this->collect()->productData()->getVar("VERSION");
	  if ($vendor eq 'openSUSE') {
	    $spdx_distro = "opensuse-leap-$version" if $distname eq 'Leap';
	    $spdx_distro = "opensuse-tumbleweed" if $distname eq 'openSUSE';
          }
	  if ($vendor eq 'SUSE') {
	    $spdx_distro = "sles-$version" if $distname eq 'SLES';
          }
        }
        $spdx_distro = "--distro $spdx_distro" if $spdx_distro;
        $cmd = "/usr/lib/build/generate_sbom $spdx_distro --product $masterpath > $masterpath.spdx.json";
        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        $out = join("\n",@{$call->[1]});
        $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
        return 1 if $status;

	# CycloneDX
        $cmd = "/usr/lib/build/generate_sbom --format cyclonedx --product $masterpath > $masterpath.cdx.json";
        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        $out = join("\n",@{$call->[1]});
        $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
        return 1 if $status;
      }
    }

    return 0;
}

1;
