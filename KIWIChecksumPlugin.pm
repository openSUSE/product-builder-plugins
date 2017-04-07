################################################################
# Copyright (c) 2008 Jan-Christoph Bornschlegel, SUSE LLC
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
package KIWIChecksumPlugin;

use strict;
use warnings;

use base "KIWIBasePlugin";
use FileHandle;
use Data::Dumper;
use Config::IniFiles;
use File::Find;

sub new {
    # ...
    # Create a new KIWIChecksumPlugin object
    # ---
    my $class   = shift;
    my $handler = shift;
    my $config  = shift;
    my $configpath;
    my $configfile;
    my $this = KIWIBasePlugin -> new ($handler);
    bless ($this, $class);
    if ($config =~ m{(.*)/([^/]+)$}x) {
        $configpath = $1;
        $configfile = $2;
    }
    if(not defined($configpath) or not defined($configfile)) {
        $this->logMsg("E", "wrong parameters in plugin initialisation\n");
        return;
    }
    ## Gather all necessary information from the inifile:
    #===
    # Issue: why duplicate code here? Why not put it into the base class?
    # Answer: Each plugin may have different options. Some only need a
    # target filename, whilst some others may need much more. I don't want
    # to specify a complicated framework for the plugin, it shall just be
    # a simple straightforward way to get information into the plugin.
    # The idea is that the people who decide on the metadata write
    # the plugin, and therefore damn well know what it needs and what not.
    # I'm definitely not bothering PMs with Yet Another File Specification
    #---
    ## plugin checksum:
    #-----------------
    #[base]
    # name = KIWIEulaPlugin
    # order = 3
    # defaultenable = 1
    #
    #[target]
    # targetdir = $PRODUCT_DIR
    # media = (list of numbers XOR "all")
    #
    my $ini = Config::IniFiles -> new(
        -file => "$configpath/$configfile"
    );
    my $name      = $ini->val('base', 'name'); # scalar value
    my $order     = $ini->val('base', 'order'); # scalar value
    my $enable    = $ini->val('base', 'defaultenable'); # scalar value
    my $targetdir = $ini->val('target', 'targetdir');
    # if any of those isn't set, complain!
    if(not defined($name)
        or not defined($order)
        or not defined($enable)
        or not defined($targetdir)
    ) {
        $this->logMsg("E", "Plugin ini file <$config> seems broken!");
        return;
    }
    $this->name($name);
    $this->order($order);
    $targetdir = $this->collect()->productData()->_substitute("$targetdir");
    if($enable != 0) {
        $this->ready(1);
    }
    $this->requiredDirs($targetdir);
    return $this;
}

sub add_checksum
{
    my $file = $_;
    return unless -f $file;

    KIWIQX::qxx("sha256sum $file >> CHECKSUMS");
}

sub execute {
    my $this = shift;
    if(not ref($this)) {
        return;
    }
    my $retval = 0;
    if($this->{m_ready} == 0) {
        return $retval;
    }
    my @targetmedia = $this->collect()->getMediaNumbers();
    my %targets;
    %targets = map { $_ => 1 } @targetmedia;
    foreach my $cd(keys(%targets)) {
        $this->logMsg("I", "Creating checksum file on medium <$cd>:");
        my $dir = $this->collect()->basesubdirs()->{$cd};
        $this->logMsg("I", "Creating checksum file on medium <$cd>: $dir");
        chdir($dir);
        find({wanted => \&add_checksum, no_chdir=>1}, "boot");
        find({wanted => \&add_checksum, no_chdir=>1}, "EFI");
        find({wanted => \&add_checksum, no_chdir=>1}, "license.tar.gz");

        $retval++;
    }

    if (-e "CHECKSUMS") {
      my $cmd = "sign -d CHECKSUMS";
      my $call = $this -> callCmd($cmd);
      my $status = $call->[0];
      my $out = join("\n",@{$call->[1]});
      $this->logMsg("I",
          "Called $cmd exit status: <$status> output: $out"
      );
    }

    return $retval;
}

1;
