################################################################
# Copyright (c) 2019 SUSE
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
package KIWIPackagesDVDPlugin;

use strict;
use warnings;

use base "KIWIBasePlugin";
use Data::Dumper;
use Config::IniFiles;
use File::Find;
use File::Basename;

sub new {
    # ...
    # Create a new KIWIPackagesDVDPlugin object
    # ---
    my ($class, $handler, $config) = @_;
    my $this = KIWIBasePlugin -> new($handler);
    bless ($this, $class);

    $this->name('KIWIPackagesDVDPlugin');
    $this->order(7);
    $this->ready(1);
    return $this;
}

sub execute {
    my $this = shift;
    if(not ref($this)) {
        return;
    }
    my $flavor = $this->collect()->productData()->getVar("FLAVOR");
    if (($flavor || '') ne 'Full') {
        return 0;
    }
    $this->logMsg("I", "Basedir " . $this->handler()->collect()->basedir());
    my @targetmedia = $this->collect()->getMediaNumbers();
    foreach my $cd (@targetmedia) {
        $this->logMsg("I", "Check <$cd>");
        my $dir = $this->collect()->basesubdirs()->{$cd};
        open(my $report, '>', "$dir.report");
        # reset the / media - just an empty repo
        open(my $products, '>', "$dir/media.1/products");
        print $report "<report>\n";
        $this->logMsg("I", "Pass $dir");
        for my $module (glob('/usr/src/packages/KIWIALL/*')) {
          $this->logMsg("I", "Found $module");
          my $bname = basename($module);
          $bname =~ s,.*-Module,Module,,;
          $bname =~ s,.*-Product,Product,,;
          $bname =~ s,.*-Liberty-Linux-,,;
          my ($module_dir) = glob("$module/*-Media$cd");
          if (!$module_dir) {
            $this->logMsg("I", "Could not find <$module/*-Media$cd>");
            next;
          }
          $this->logMsg("I", "Copy <$module_dir>");
          system("cp -a $module_dir $dir/$bname");
          open(my $fd, '<', "$module_dir.report");
          while (<$fd>) {
            my $line = $_;
            next if $line =~ m,</?report>,;
            print $report $line;
          }
          close($fd);
          open($fd, '<', "$module_dir/media.1/products");
          my $line = <$fd>;
          $line =~ s,^/,/$bname,;
          print $products $line;
          close($fd);
        }
        print $report "</report>\n";
        close($report);
        close($products);

        # drop main repodata on on fedora
        system("rm -rf $dir/repodata") if -e "$dir/.discinfo";

        # create SBOM data, if the build tool is available
        my $generate_sbom;
        $generate_sbom = "/usr/lib/build/generate_sbom" if -x "/usr/lib/build/generate_sbom";
        # prefer server version if available
        $generate_sbom = "perl -I /.build /.build/generate_sbom" if -e "/.build/generate_sbom";
        if ($generate_sbom) {
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
              $spdx_distro = "suse-alp" if $distname =~ /^ALP/m;
            }
          }
          $spdx_distro = "--distro $spdx_distro" if $spdx_distro;
          my $cmd = "$generate_sbom $spdx_distro --product $dir > $dir.spdx.json";
          my $call = $this -> callCmd($cmd);
          my $status = $call->[0];
          my $out = join("\n",@{$call->[1]});
          $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
          return 1 if $status;

          # CycloneDX
          $cmd = "$generate_sbom --format cyclonedx --product $dir > $dir.cdx.json";
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
