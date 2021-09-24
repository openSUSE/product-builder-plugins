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
package KIWIDnfRepoclosurePlugin;

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

    $this->name('KIWIDnfRepoclosurePlugin');
    $this->order(99);
    $this->ready(1);
    return $this;
}

sub execute {
    my $this = shift;
    return unless ref($this);

    my $collect = $this->collect();
    my $enabled = $this->collect()->productData()->getOpt("RUN_DEPENDENCY_CHECK");
    return 0 if ($enabled || '') ne 'error' && ($enabled || '') ne 'warn';

    my @archs = keys(%{$collect->{m_archlist}->{m_archs}});

    $this->logMsg("I", "Basedir " . $this->handler()->collect()->basedir());
    my @targetmedia = $this->collect()->getMediaNumbers();
    my $validation_failed;
    foreach my $cd (@targetmedia) {
        my $dir = $this->collect()->basesubdirs()->{$cd};
        next unless -d "$dir/repodata";
        foreach my $arch (@archs) {
             next if $arch eq 'noarch';
             $this->logMsg("I", "Verifing dependencies in <$cd>");
             $this->logMsg("I", "Pass $dir");
             my $cmd = "dnf repoclosure --arch=noarch --arch=$arch --repofrompath=dnf_repoclosure,file://$dir --repo=dnf_repoclosure --check=dnf_repoclosure 2>&1"; # verbose output
             $this->logMsg("I", "Executing command <$cmd>");
             my $call = $this -> callCmd($cmd);
             my $status = $call->[0];
             if ($status) {
                 my $out = join("\n",@{$call->[1]});
                 $this->logMsg("W", "Validation failed: $out");
                 $validation_failed = 1;
             }
        }
    }
    if ($enabled eq 'error' && $validation_failed) {
        $this->logMsg("E", "Any validation failed and check is enforced");
        return 1;
    }
    return 0;
}

1;
