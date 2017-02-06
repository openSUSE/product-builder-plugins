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
    my $rezip      = $ini->val('base', 'rezip');
    my $enable     = $ini->val('base', 'defaultenable');
    my @params     = $ini->val('options', 'parameter');
    my $gzip       = $ini->val('target', 'compress');
    # if any of those isn't set, complain!
    if(not defined($name)
        or not defined($order)
        or not defined($createrepo)
        or not defined($rezip)
        or not defined($enable)
        or not defined($gzip)
    ) {
        $this->logMsg("E",
            "Plugin ini file <$config> seems broken!"
        );
        return;
    }
    my $params = "";
    foreach my $p(@params) {
        $p = $this->collect()->productData()->_substitute("$p");
        $params .= "$p ";
    }
    # add local kwd files as argument
    my $extrafile = abs_path($this->collect()->{m_xml}->{xmlOrigFile});
    $extrafile =~ s/.kiwi$/.kwd/x;
    if (-f $extrafile) {
        $this->logMsg("W", "Found extra tags file $extrafile.");
        $params .= "-T $extrafile ";
    }
    $this->name($name);
    $this->order($order);
    $this->{m_createrepo} = $createrepo;
    $this->{m_rezip} = $rezip;
    $this->{m_params} = $params;
    $this->{m_compress} = $gzip;
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
    my $descrdir = $coll->productData()->getInfo("DESCRDIR");
    my $cpeid = $coll->productData()->getInfo("CPEID");
    my $repoid = $coll->productData()->getInfo("REPOID");
    my $createrepomd = $coll->productData()->getVar("CREATE_REPOMD");
    my $metadataonly = $coll->productData()->getVar("RPMHDRS_ONLY");
    my $params = "$this->{m_params} -H" ? $metadataonly eq "true" : "$this->{m_params}";
    ## this ugly bit creates a parameter string from a list of directories:
    # param = -d <dir1> -d <dir2> ...
    # the order is important. Idea: use map to make hash <dir> => -d for
    # all subdirs not ending with "0" (those are for metafile unpacking
    # only). The result is evaluated in list context be reverse, so
    # there's a list looking like "<dir_N> -d ... <dir1> -d" which is
    # reversed again, making the result '-d', '<dir1>', ..., '-d', '<dir_N>'",
    # after the join as string.
    # ---
    if ( $createrepomd && $createrepomd eq "true" ) {
        my $distroname = $coll->productData()->getInfo("DISTRIBUTION")."."
                . $coll->productData()->getInfo("VERSION");
        my $result = $this -> createRepositoryMetadata(
            \@paths, $repoid, $distroname, $cpeid
        );
        # return values 0 || 1 indicates an error
        if ($result != 2) {
            return $result;
        }
    }
    # insert translation files
if (0) {
    my $trans_dir  = '/usr/share/locale/en_US/LC_MESSAGES';
    my $trans_glob = 'package-translations-*.mo';
    foreach my $trans (glob($trans_dir.'/'.$trans_glob)) {
        $trans = basename($trans, ".mo");
        $trans =~ s,.*-,,x;
        $cmd = "/usr/bin/translate_packages.pl $trans "
            . "< packages.en "
            . "> packages.$trans";
        $call = $this -> callCmd($cmd);
        $status = $call->[0];
        if($status) {
            my $out = join("\n",@{$call->[1]});
            $this->logMsg("E",
                "Called <$cmd> exit status: <$status> output: $out"
            );
            return 1;
        }
    }
    # one more time for english to insert possible EULAs
    $cmd = "/usr/bin/translate_packages.pl en "
        . "< packages.en "
        . "> packages.en.new && "
        . "mv packages.en.new packages.en";
    $call = $this -> callCmd($cmd);
    $status = $call->[0];
    if ($status) {
        my $out = join("\n",@{$call->[1]});
        $this->logMsg("E",
            "Called <$cmd> exit status: <$status> output: $out"
        );
        return 1;
    }
}
    if (-x "/usr/bin/openSUSE-appstream-process") {
        foreach my $p (@paths) {
            $cmd = "/usr/bin/openSUSE-appstream-process";
            $cmd .= " $p";
            $cmd .= " $p/$descrdir";
            $call = $this -> callCmd($cmd);
            $status = $call->[0];
            my $out = join("\n",@{$call->[1]});
            $this->logMsg("I",
                "Called <$cmd> exit status: <$status> output: $out"
            );
        };
    }
    if($this->{m_compress} =~ m{yes}i) {
        foreach my $pfile(glob("packages*")) {
            if(system("gzip", "--rsyncable", "$pfile") == 0) {
                unlink "$pfile";
            } else {
                $this->logMsg("W",
                    "Can't compress file <$pfile>!"
                );
            }
        }
    }
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
    foreach my $p (@{$paths}) {
        $cmd = "$this->{m_createrepo}";
        $cmd .= " --unique-md-filenames";
        $cmd .= " --checksum=sha256";
        $cmd .= " --no-database";
        $cmd .= " --repo=\"$repoid\"" if $repoid;
        $cmd .= " --distro=\"$cpeid,$distroname\"" if $cpeid && $distroname;
        $cmd .= " $p";
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
        $cmd = "$this->{m_rezip} $p ";
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
            $cmd .= " $p";
            $cmd .= " $p/repodata";

            $call = $this -> callCmd($cmd);
            $status = $call->[0];
            my $out = join("\n",@{$call->[1]});
            $this->logMsg("I",
                "Called $cmd exit status: <$status> output: $out"
            );
        }
        if ( -f "/usr/bin/add_product_susedata" ) {
            my $kwdfile = abs_path(
                $this->collect()->{m_xml}->{xmlOrigFile}
            );
            $kwdfile =~ s/.kiwi$/.kwd/x;
            $cmd = "/usr/bin/add_product_susedata";
            $cmd .= " -u"; # unique filenames
            $cmd .= " -k $kwdfile";
            $cmd .= " -p"; # add diskusage data
            $cmd .= " -e /usr/share/doc/packages/eulas";
            $cmd .= " -d $p";
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
        }
    }
    # merge meta data
    $cmd = "mergerepo_c";
    foreach my $p (@{$paths}) {
      $cmd .= " --repo=$p";
    }
    $call = $this -> callCmd($cmd);
    $status = $call->[0];
    my $out = join("\n",@{$call->[1]});
    $this->logMsg("I", "Called $cmd exit status: <$status> output: $out");
    # cleanup
    foreach my $p (@{$paths}) {
      system("rm", "-rf", $p);
    }
    # move merge repo in place
    system("mv", "merged_repo/repodata", "$masterpath/repodata");
    return 2;
}

1;
