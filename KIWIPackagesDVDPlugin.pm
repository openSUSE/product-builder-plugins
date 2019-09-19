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
    if (($flavor || '') ne 'Packages-DVD') {
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
            print "$module_dir.report $line";
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
    }
    return 0;
}

1;
