################################################################
# Copyright (c) 2014, 2015 SUSE LLC
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
package KIWIBootIsoPlugin;

use strict;
use warnings;

use base "KIWIBasePlugin";
use Data::Dumper;
use Config::IniFiles;
use File::Find;
use FileHandle;
use Carp;
use File::Basename qw /dirname/;

sub new {
    # ...
    # Create a new KIWIMiniIsoPlugin object
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
    if ((! $configpath) || (! $configfile)) {
        $this->logMsg("E",
            "wrong parameters in plugin initialisation\n"
        );
        return;
    }
    ## plugin content:
    #-----------------
    #[base]
    # name = KIWIEulaPlugin
    # order = 3
    # defaultenable = 1
    #
    #[target]
    # targetfile = content
    # targetdir = $PRODUCT_DIR
    # media = (list of numbers XOR "all")
    #
    my $ini = Config::IniFiles -> new (
        -file => "$configpath/$configfile"
    );
    my $name   = $ini->val('base', 'name');
    my $order  = $ini->val('base', 'order');
    my $enable = $ini->val('base', 'defaultenable');
    # if any of those isn't set, complain!
    if (not defined($name)
        or not defined($order)
        or not defined($enable)
    ) {
        $this->logMsg("E",
            "Plugin ini file <$config> seems broken!\n"
        );
        return;
    }
    $this->name($name);
    $this->order($order);
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
        return 0;
    }
    my $isboot = $this->collect()->productData()->getVar("FLAVOR");
    if(not defined($isboot)) {
        $this->logMsg("W", "FLAVOR not set?");
        return 0;
    }
    if ($isboot !~ m{boot}i) {
        $this->logMsg("I",
            "Nothing to do for media type <$isboot>"
        );
        return 0;
    }
    
    my @rootfiles;
    find(
        sub { find_cb($this, '.*/root$', \@rootfiles) },
        $this->handler()->collect()->basedir()
    );
    $this->removeRepoData();
}

sub removeRepoData {
    my $this = shift;
    my $basedir = $this->handler()->collect()->basedir();

    $this->logMsg("I", "removing repodata from <$basedir>");
    system("find", $basedir, "-name", "repodata", "-a", "-type", "d", "-exec", "rm", "-rv", "{}", ";");
    system("find", $basedir, "-name", ".treeinfo", "-a", "-type", "f", "-exec", "rm", "-v", "{}", ";");
    system("find", $basedir, "-name", "media.repo", "-a", "-type", "f", "-exec", "rm", "-v", "{}", ";");
    return 0;
}

sub find_cb {
    my $this = shift;
    return if not ref($this);

    my $pat = shift;
    my $listref = shift;
    if(not defined($listref) or not defined($pat)) {
        return;
    }
    if($File::Find::name =~ m{$pat}x) {
        push @{$listref}, $File::Find::name;
    }
    return $this;
}

1;
