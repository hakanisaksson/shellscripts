#!/usr/bin/perl -w
#
# vobtool.pl
# by hakan.isaksson at init.se, 2012
#
# Tool for handling ClearCase vobs
#
# swedish characters are coded in sv.iso5589-1
#
# installation of Date::Calc on cygwin:
#  perl -MCPAN -e shell
#  force install Date::Calc
#  quit
#
# installation of Date::Calc on Solaris 10
#  mkdir ~/perlmods
#  wget Date-Calc-6.3.tar.gz from cpan
#  gunzip & untar
#  perl Makefile.PL PREFIX=~/perlmods
#  make test
#  set env variable PERL5LIB
#
# Create vobtool.save/options.txt
# the following variables should be defined, as they are not defined in the script
#  STGLOC=
#  RGYPASS=
#  SAMBA_SHARE=
# 
# This script assumes interop env with samba, if that is not the case, let SAMBA_SHARE be undefined.
#
use strict;
use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;
use File::Basename;
use Date::Calc qw/:all/;
use Data::Dumper;

=pod

=head1 NAME

vobtool.pl

=head1 SYNOPSIS

vobtool.pl [--help] [<options>] <vobtag>

=head1 OPTIONS

=over 10

=item B<--age> <days>

Only show views older than -age <days> ago. Valid numbers are  -1 to N, where -1 is unknown.

=item B<--chflevel> <level>

Upgrade vob feature level to <level>

=item B<--debug>

Debug mode

=item B<--delimiter>

Change delimiter chatacter between fields with --list

=item B<--fields> <fields>

Select fields to show with --list
Default "tag,gpath"
Possible fields:
"age,tag,gpath,host,access,active,region,uuid,apath,schema,family,flevel,owner,group,created,createdby"
and
"last,lastby,lastage" if "-i -i" was used to gather information

=item B<--findview> <uuid>

Search all vobs for a specific view uuid. Lists all vobs that have references to that view.
Useful so you don't have to do rmview on all vobs if you only have the uuid.

=item B<--help>

Show help.

=item B<--init>

Runs
cleartool lsvob -l 
Saves the result in a textfile,
that can be used by this tool until you feel the need to update it with --init again. 
Use the "-i" option twice for a deeper scan, that does lshistory on all vobs to
find the last changed time and user. Necessary to use the fields "last,lastby,lastage".

=item B<--list>

List vobs and age.

=item B<--man>

Show man page, more verbose than --help.

=item B<--new>

Create a new vob on predefined storage.

=item B<--old> <nr>

Show a previously saved list of vobs. The lists are rotated, the most recent is always 1, then 2 and so on up to the max keep limit. Only used with --list.

=item B<--region> <region>

Can be used to list vobs from another region than the default, note that the vobs for that region must
first be saved with "-i --region region" prior to listing. Also changes the default listing fields.

=item B<--replace> <vobtag>

Restore a vob with the "-replace" option (not necessary if the vob was unregistered).

=item B<--restore> <vobtag>

Restore a clearcase vob, the vob must have been removed with --unregister.
OBS! Use with caution. ClearCase server (and all it's processes) must be restarted after registering a vob.

=item B<--save> <vobtag>

Save information for specified vob, i.e. saves the output from lsvob -l to vobtool.save/descvob.<tag>.txt 

=item B<--test>

Testmode. No changes are made.

=item B<--unregister> <vobtag>

Removes a vob by unregistering and deleting the vobtag.
The actual vob-files are left as they are.
Saves vob description to a file that can be used with --restore
OBS! Use with caution. ClearCase server (and all it's processes) must be stopped after unregistering a vob,
also all clients that have any connetion to this vob must be restarted.

=item B<--uuid> <uuid>

See --findview

=item B<--yes>

Answer yes to all questions.

=back

=head1 DESCRIPTION

vobtool.pl is an advanced tool for listing and manipulating ClearCase vobs.
Designed to work on unix, windows (with cygwin).
Important to know that this tool always work with cached information that might not be up to date.
Run "vobtool.pl -i" to initialize or update the cache.

=head1 EXAMPLES

Create or update vob list:
vobtool.pl -i

List all vobs, feature level and schema:
vobtool.pl -l --fields="vob,gpath,flevel,schema" 

=cut

my $DEBUG=0;        ### Debugmode
my $TEST=0;         ### Testmode
my $SHOW_AGE=0;     ### Only show views older than this date
my $CHFLEVEL=0;     ### Change feature level
my $LIST=0;         ### List views
my $INIT=0;         ### Init input file
my $UNREG=0;        ### Unregister and remove vobtag
my $RESTORE=0;      ### Restore vobtag
my $REPLACE=0;      ### Restore vob with replace
#my $REMOVE=0;       ### Delete vob
my $SAVE=0;         ### Save view description
my $SHOW=0;         ### Show saved view description
my $NEW=0;          ### Create new vob
my $YES=0;          ### answer 'yes' to all questions
my $FINDVIEW=0;     ### find view uuid
my $FORCE=0;        ### Ignore some errors
my $OSTYPE;         ### unix, cygwin or dos
my $REGION="";      ### Change region (unused)
my $OLD=0;          ### Show old list
my $KEEP=20;        ### Number of list versions to keep

my $DELIMITER;      ### Field delimiter
my $FIELDS;         ### List fields
my $HOST;           ### Server host (only show vobs registered to this server host)

my $ct="cleartool";

my ($logfile,$vobsfile,$vobsdesc,$optsfile);
my ($VOBTAG,$STGLOC,$RGYPASS,$SAMBA_SHARE,$SAVEDIR);

my %vobs;        ### Global list of vobs

GetOptions(

    "age=s"      => \$SHOW_AGE,
    "chflevel=s" => \$CHFLEVEL,
    "d|debug+"    => \$DEBUG,
    "delimiter=s"=> \$DELIMITER,
#   "f|force"    => \$FORCE,
    "fields=s"   => \$FIELDS,
    "findview=s" => \$FINDVIEW,
    "host=s"     => \$HOST,
    "i|init+"     => \$INIT,
    "list"       => \$LIST,
    "new"        => \$NEW,
    "old=s"      => \$OLD,
#   "remove"     => \$REMOVE,
    "region=s"   => \$REGION,
    "replace"    => \$REPLACE,
    "r|restore"  => \$RESTORE,
    "save"       => \$SAVE,
    "s|show"     => \$SHOW,
    "test"       => \$TEST,
    "unregister" => \$UNREG,
    "uuid=s"     => \$FINDVIEW,
    "yes"        => \$YES,
    "h|help"     => sub {pod2usage(-verbose => 1)},
    "man"        => sub {pod2usage(-verbose => 2)},
    ) || pod2usage();

#
# Initialize
#
$VOBTAG = $ARGV[0];
$VOBTAG=basename($VOBTAG) if defined $VOBTAG;
$OSTYPE=detect_cygwin();

$SAVEDIR=dirname($0)."/vobtool.save";
$SAVEDIR=File::Spec->rel2abs($SAVEDIR);
$logfile=$SAVEDIR."/voblog.txt";
$vobsfile=$SAVEDIR."/vobs.txt";
$vobsdesc=$SAVEDIR."/vobsdesc.txt";
$optsfile=$SAVEDIR."/options.txt";
read_opts($optsfile);

if ($REGION ne "") {
    $vobsfile=$SAVEDIR."/$REGION.vobs.txt";
    $FIELDS="vob,gpath" if ! defined $FIELDS;
}

if (! defined $HOST ) {
    $HOST=Sys::Hostname::hostname();
}
$FIELDS="vob,gpath" if ! defined $FIELDS;  ### Default List fields
$DELIMITER=" " if ! defined $DELIMITER; ### Default delimiter

debug("SAVEDIR=$SAVEDIR");
debug("VOBTAG=$VOBTAG") if defined $VOBTAG;
debug("OSTYPE=$OSTYPE");
debug("DELIMITER=<$DELIMITER>");
debug("FIELDS=$FIELDS");
debug("HOST=$HOST");
debug("RGYPASS=$RGYPASS") if defined $RGYPASS;
debug("STGLOC=$STGLOC") if defined $STGLOC;
debug("SAMBA_SHARE=$SAMBA_SHARE") if defined $SAMBA_SHARE;

msg("WARNING: Incompatible environment, run on unix or in cygwin in windows") if (($OSTYPE ne "cygwin")and($OSTYPE ne "unix"));

sub msg {
    my $msg = shift;
    print $msg."\n" if defined $msg;
}

sub debug {
    my $msg = shift;
    my $level = shift;
    if (defined $level ) { 
	msg ("DEBUG: ".$msg) if $DEBUG >= $level;
    } else {
	msg ("DEBUG: ".$msg) if $DEBUG;
    }
}

sub error {
    msg ("ERROR: ".shift(@_));
    exit(1);
}

sub logmsg {
    my $msg = shift;
    return if $TEST;
    my $now = sprintf "%4d-%02d-%02d %02d:%02d:%02d", Today_and_Now();
    open(LOG,">>$logfile") or error("Can't open $logfile: $!");
    print LOG $now." ".$msg."\n";
    close(LOG);
    debug("logmsg: $now $msg");
}

sub shell {
    my $cmd = shift;
    my $err = 0;
    if (! $TEST ) {
        debug("$cmd");
        system($cmd);
        $err= $?;
    } else {
        debug("#$cmd") if $TEST;
    }
    return $err;
}

sub detect_cygwin {
    my $type;
    my $out = `uname`;
    chomp($out);
    if ($? eq 0 ) {
        if ($out =~ /CYGWIN/) {
            $type="cygwin";
        } else {
            $type="unix";
        }
    } else {
        $type="dos";
    }
    return $type;
}

sub cygpath {
    my $path=shift;
    my $out;
    if ($OSTYPE eq "cygwin") {
        $out=`cygpath -w $path`;
        chomp($out);
    } else {
        $out=$path;
    }
    return $out;
}

sub escpath {
    my $path=shift;
    if ($OSTYPE eq "cygwin") {
        $path=~ s/\\/\\\\/g;
    }
    return $path;
}

#
# Ask the user for input
#
# usage: ask_yn ($question, $defaultanswer)
#   retuns answer
#
sub ask_yn {
    my $question = shift;
    my $def = "Y";
    my $ans;

    if ( $YES ) {
        $ans= $def;
        print "$question [$def]\n";
    } else {
        print "$question";
        print " [$def]: " if defined $def;
        $ans=<STDIN>;
        chomp($ans);
        $ans = $def if $ans eq "";
    }
    return 1 if uc($ans) =~ /^Y/;
    return 0 if uc($ans) =~ /^N/;
    error("invalid answer: $ans");
}


#
# Ask, run cmd and exit on error
#
sub ask_shell {
    my $cmd = shift;
    my $warn = shift;
    my $err;

    if (ask_yn("$cmd")) {
        $err=shell($cmd);
        if ( defined $warn ) {
        msg("WARNING: Failed cmd: $cmd") if $err;
        } else {
        error("Failed cmd: $cmd") if $err;
        }
        logmsg($cmd);
    }

}

#
# Read options and define variables unless they have already been set by arguments
#
sub read_opts {
    my $file = shift;
    debug("read_opts: $file");

    debug("read_opts: open $file",2);
    if ( open(F,"<$file") ) {
	binmode(F);
	while (<F>) {
	    chomp;
	    if (/^(\w*)\=([\w\:\.\\\/\-\_,]*)/) {
		my ($var,$val) = ($1,$2);
		$val=~ s/\\/\\\\/g if ($1 eq "SAMBA_SHARE");
		eval("\$$var=\'$val\' if ! defined \$$var;");
		debug("read_opts: \$$var=\'$val\' if ! defined \$$var;",2);
	    }
	}
	close(F);
    } else {
	msg("WARNING: Can't open $file: $!\nCreate $file and define the following variables: STGLOC,RGYPASS,SAMBA_SHARE");
    }
}

#
# Rotate $file to $file.$nr up to $keepnr
#
sub rotate_file {
    my $file=shift;
    my $keepnr=shift;

    debug("rotate_file: $file $keepnr");
    return if ! -e $file;

    my $dir= dirname($file);
    error("Failed to find dir $dir") if ! -d $dir;

    my $old=$file.".";
    my $gz="";
    my $new;
    my $num=$keepnr;
    while ( $num ge 1 ) {
        $new=$num;
        $num--;
        my $of="${old}${num}${gz}";
        $of = "$file" if $num eq 0;
        if ( -e "$of" ) {
            shell("mv $of ${old}${new}${gz}") if $OSTYPE ne "dos";
            shell("move $of ${old}${new}${gz}") if $OSTYPE eq "dos";
        }
    }
}

#
# Save a list of all vobs with -long description to $vobsfile
#
sub init_vobs {
    debug("init_vobs");
    my $err=0;
    my $cmd="mkdir -p $SAVEDIR";

    $err=shell($cmd) if ! -d $SAVEDIR;
    error("Failed cmd: $cmd") if $err;

    rotate_file($vobsfile, $KEEP);
    rotate_file($vobsdesc, $KEEP) if ($REGION eq "");
    $cmd="$ct lsvob -l > $vobsfile";
    $cmd="$ct lsvob -l -region $REGION > $vobsfile" if ($REGION ne "");

    $err=shell($cmd);
    if ($err) {
        #shell("rm $vobsfile");
        msg("cleartool returned error: $cmd");
    }
    return if ($REGION ne "");

    msg "Scanning vobs....";
    debug("init_vobs: open $vobsfile",2);
    open(F,"<$vobsfile") or error("Can't open $vobsfile: $!");
    shell("echo > $vobsdesc");
    while (<F>) {
	chomp;
	$_ =~s/\r//g;
        if (/^Tag:\s+([\\\w\-\.\$\/åäö]+)/) {
            my $tag=$1;
	    my $btag=basename($tag);
            my $vobhist=$SAVEDIR."/lshist.$btag.txt"; 

	    msg "$tag";
	    $cmd="$ct desc -l vob:".escpath($tag)." >> $vobsdesc";
	    #$cmd="$ct.desc desc -l vob:$tag >> $vobsdesc";
	    $err=shell($cmd);
	    msg("WARNING: cleartool returned error: $cmd") if ($err);

            #next if $tag =~ /ais/;
            if ($INIT > 1 ) {
            $cmd="$ct setview -exec \"cleartool lshist -a  -fmt '%d %u %e %n\\n' $tag\" vobadm|grep -v lock| sort -n| tail -100 > $vobhist";
            $err=shell($cmd);
            msg("WARNING: cleartool returned error: $cmd") if ($err);
            }
        }
    }
       
}

sub read_vobs {
    my $file = shift;
    debug("read_vobs: $file");
    my $tag="";
    my $btag;
    my ($y,$m,$d)= Today();
    $file=$SAVEDIR."/vobs.txt.$OLD" if $OLD > 0;
    $file=$SAVEDIR."/$REGION.vobs.txt.$OLD" if $OLD > 0 and $REGION ne "";
    debug("read_vobs: open $file",2);
    open(F,"<$file") or error ("can't open $file: $!\nRun $0 --init to create $file.");
    binmode(F);
    while (<F>) {
        chomp;
        $_ =~s/\r//g;
        if (/^Tag:\s+([\\\w\-\.\$\/åäö]+)/) {
            $tag=$1;
	    $btag=basename($tag); $btag =~ s/^\\//g;
	    $vobs{$btag}{tag}=$btag;
	    $vobs{$btag}{vob}=$tag;
        }
        $vobs{$btag}{gpath}=$1 if /\s+Global path:\s(.+)/;
        $vobs{$btag}{region}=$1 if /\s+Region:\s(.+)/;
        $vobs{$btag}{host}=$1 if /\s+Server host:\s(.+)/;
        $vobs{$btag}{uuid}=$1 if /\s+Vob tag replica uuid:\s(.+)/;
        $vobs{$btag}{active}=$1 if /\s+Active:\s(.+)/;
        $vobs{$btag}{apath}=$1 if /^Vob server access path:\s(.+)/;
        $vobs{$btag}{hpath}=$1 if /^Vob server access path:\s(.+)/;
        $vobs{$btag}{access}=$1 if /\s+Access:\s(.+)/;

    }
    close(F);

    $file=$vobsdesc;
    $file=$SAVEDIR."/vobsdesc.txt.$OLD" if $OLD > 0;
    open(F,"<$file") or error ("can't open $file: $!\nRun $0 --init to create $file.");
    debug("read_vobs: open $file",2);
    binmode(F);
    while (<F>) {
        chomp;
        $_ =~s/\r//g;
	if (/^versioned object base\s+\"([\\\w\-\.\$\/åäö]+)\"/) {
	    $tag=$1; 
	    $btag=basename($tag);
	    debug("read_vobs: found $tag",2);
	}
        $vobs{$btag}{schema}=$1 if /\s*schema version:\s*(\d+)/;
        $vobs{$btag}{family}=$1 if /\s*VOB family feature level:\s*(\d+)/;
        $vobs{$btag}{flevel}=$1 if /\s*FeatureLevel\s*=\s*(\d+)/;
        $vobs{$btag}{owner}=$1 if /\s+owner\s(\w+)/;
        $vobs{$btag}{group}=$1 if /\s+group\s(\w+)/;
	if (/\s+created\s+(\d+)\-(\d+)-(\d+)T.* by (.*)/) {
	    $vobs{$btag}{created}="$1-$2-$3";
	    my $days = Delta_Days($1,$2,$3, $y,$m,$d);
            my $pdays = sprintf("%05d", $days);
            $vobs{$btag}{age}=$pdays;
	    my $by = $4; 
	    $by =~ s/\(//g;
	    $by =~ s/\)//g;
	    $vobs{$btag}{createdby}=$by;
	    debug("read_vobs: created=$1-$2-$3 days=$days createdby=$by",2) if defined $1;
	}
	### find view uuids
	if (/\s+([\w\-]+):(.*) \[uuid ([\w\.:]+)\]/) {
	    #debug("uuid $1 $2 $3");
	    my %view;
	    $view{host}=$1;
	    $view{path}=$2;
	    $view{uuid}=$3;
	    push (@{$vobs{$btag}{views} },   \%view );
	}

    }
    close(F);

    foreach my $tag (keys %vobs) {
	my $vobhist=$SAVEDIR."/lshist.${tag}.txt";
	if ( -f $vobhist ) {
	    open(F,"<$vobhist") or error ("can't open $vobhist: $!\nRun $0 --init --init to create lshist.");
	    binmode(F);
	    my $last="";
	    my $lastage=0;
	    my $lastby="";
	    while (<F>) {
		chomp;
		my @parts = split(/\s+/);
		my $str = $parts[0]." ".$parts[1];
		if ( $str =~ /^(\d+)\-(\d+)\-(\d+)T.+\s+(\w+)/) {
#debug("date $1,$2,$3 : $_ $vobhist");
		    my $days =  Delta_Days($1,$2,$3, $y,$m,$d);
		    if ( (($days <= $lastage) and ($4 ne "vobadm")) or $lastage eq 0) {
			$last="$1-$2-$3";
			$lastby=$4;
			$lastage=$days;
			debug("read_vobs: last=$last <= $1-$2-$3 lastage=$lastage <= $days $lastby",3);
		    }
		}
	    }
	    $vobs{$tag}{'last'}=$last;
	    $vobs{$tag}{lastage}=$lastage if $lastage ne 0;
	    $vobs{$tag}{lastby}=$lastby;
	} else {
	    debug("no $vobhist found for $tag",3);
	}
    }
    
    #print Dumper(\%vobs);
    #exit;
}

#
# Load or Show saved description of vob
#
sub load_vob {
    my $vtag=shift;
    debug("load_vob: $vtag");
    my $descfile = $SAVEDIR."/descvob.".$vtag.".txt";
    open(F,"<$descfile") or error("Can't open $descfile: $!");
    binmode(F);
    while (<F>) {
        chomp;
        $_ =~s/\r//g;
        #msg($_);# if ! $RESTORE;
        ### load vob for restore_vob
        $vobs{$vtag}{schema}=$1 if /\s*schema version:\s*(\d+)/;
        $vobs{$vtag}{family}=$1 if /\s*VOB family feature level:\s*(\d+)/;
        $vobs{$vtag}{flevel}=$1 if /\s*FeatureLevel\s*=\s*(\d+)/;
        $vobs{$vtag}{owner}=$1 if /\s+owner\s(\w+)/;
        $vobs{$vtag}{group}=$1 if /\s+group\s(\w+)/;
	$vobs{$vtag}{gpath}=$1 if /VOB storage global pathname \"(.+)\"/;
	if ( /VOB storage host.pathname \"(.+)\"/ ) {
	    $vobs{$vtag}{hpath}=$1;
	    $vobs{$vtag}{apath}=$1 if ($vobs{$vtag}{hpath} =~ /[\w]+:(.+)/);
	}
    }
    close(F);

    #print Dumper($vobs{$vtag});
    #exit if ! $RESTORE;
}


#
# List selected view fields and sort output
#
sub list_vobs {
    debug("list_vobs:");
    my @out;
    foreach my $btag (keys %vobs) {

        my $str="";
	
	my @fields = split(/,/,$FIELDS);
	foreach my $f (@fields) {
	    if (defined $vobs{$btag}{$f}) {
                $str.=$vobs{$btag}{$f}.$DELIMITER;
	    } else {
		debug "WARNING: $btag: field $f undefined";
	    }
	}
	push(@out, $str);
    }

    foreach my $s (sort(@out)) {
        msg $s;
    }
}

#
# Find view uuid in vobs
#
sub find_uuid {
    my $find = shift;
    debug("find_uuid: $find");

    my $prefix="/vobs/";
    #$prefix="\\" if $OSTYPE ne "unix";
    foreach my $btag (keys %vobs) {

	if ( defined $vobs{$btag}{views}) {
	    my @views =  @{ $vobs{$btag}{views} };
	    foreach my $v (@views) {
		if (defined $v) {  
		    debug($vobs{$btag}{vob}.": view uuid ".$v->{uuid});
		    my $str=$v->{uuid}.$DELIMITER.$v->{path}.$DELIMITER."@".$v->{host};
		    msg $vobs{$btag}{vob}.": ".$str if $find eq $v->{uuid};
		}
	    }
	}
    }
    exit;
}

#
# Show vob data
#
sub show_vob {
    my $vob = shift;
    if ( defined $vob ) {
	debug("show_vob: $vob");
	print Dumper($vobs{$vob});
    } else {
	print Dumper(\%vobs);
    }
    exit;
}

#
# Save long descripton for specific vob
#
sub save_vob {
    my $vtag=shift;
    debug("save_vob: $vtag");
    error("vob not found: $vtag") if ! defined $vobs{$vtag}{vob};
    my $vob = $vobs{$vtag}{vob};
    my $descfile = $SAVEDIR."/descvob.".$vtag.".txt";
    rotate_file($descfile, $KEEP);
    my $cmd="$ct desc -long vob:$vob > $descfile";
    my $err = shell($cmd);
    if ($err and !$FORCE) {
        shell("rm $descfile");
        error("Failed cmd: $cmd");
    }
    debug("save_vob: created $descfile",2);
}

sub new_vob {
    my $vtag = shift;
    my $cmd;

    debug("new_vob: $vtag");
    error("vob $vtag already exists") if defined $vobs{$vtag}{vob};
    ### double check
    $cmd="$ct lsvob -short | grep -w $vtag";
    error("vob $vtag already exists") if (shell($cmd) eq 0) and ! $TEST;
    ### triple check
    error("/vobs/$vtag already exists") if (($OSTYPE eq "unix") and (-d "/vobs/$vtag"));
    ### check stgloc
    
    #$cmd="cleartool lsstg -vob|  awk '{print \$1}'| grep -w $STGLOC > /dev/null";
    $cmd="cleartool lsstg -vob| grep -w $STGLOC | awk '{print \$2}' ";
    debug($cmd);
    my $gpath="";
    $gpath=`$cmd`;
    chomp($gpath);
    error("Can't find vob storage location: $STGLOC") if ($gpath eq "");
    $gpath=$gpath."/$vtag.vbs";
    debug("GPATH=$gpath");
    
    umask 002;

    my $pass="";
    $pass="-password $RGYPASS" if $YES and defined $RGYPASS;
    my $wgpath;

    $cmd="cleartool mkvob -tag /vobs/$vtag -public -stgloc nasvob_stgloc";
    ask_shell($cmd);
    $cmd="cleartool mount /vobs/$vtag";
    ask_shell($cmd);
    if (defined $SAMBA_SHARE) {
	$wgpath=$SAMBA_SHARE.$vtag.".vbs";
	$cmd="$ct mktag -vob -tag \\\\$vtag -region windows_region -public $pass -host $HOST -gpath $wgpath $gpath";
	if ( -d $gpath) {
	    ask_shell($cmd);
	} else {
	    error("Can't find dir $gpath");
	}
    }
    exit;
}

sub register_vob {
    my $vtag = shift;
    debug("register_vob: $vtag not implemented, use --restore");

    exit;

}


#
# register and mktag
#
sub restore_vob {
    my $vtag = shift;    
    my $cmd;
    error("Missing vobtag, usage: $0 -restore <vobtag>") if ! defined $vtag;
    debug("restore_vob: $vtag");

    my $vob = $vobs{$vtag}{vob};
    error("unknown vobtag: $vtag") if ! defined $vob;
    load_vob($vtag);
    
    my $path=escpath($vobs{$vtag}{apath});
    my $gpath=escpath($vobs{$vtag}{gpath});

    my $repl="";
    $repl="-replace" if $REPLACE;
    my $pass="";
    $pass="-password $RGYPASS" if $YES and defined $RGYPASS;

    umask 0002;
    msg("umask 0002");
    #$cmd="$ct umount $vob";
    #ask_shell($cmd);
    $cmd="$ct register -vob $repl -host $HOST -hpath $path $path";
    ask_shell($cmd);
    $cmd="$ct mktag -vob $repl -tag $vob -public $pass -host $HOST -gpath $gpath $path";
    ask_shell($cmd);
    if (defined $SAMBA_SHARE) {
	my $wgpath=escpath($SAMBA_SHARE."".${vtag}.".vbs");
	$wgpath=~ s/\\/\\\\/g;

	$cmd="$ct mktag -vob -tag \\\\$vtag -region windows_region -public $pass -host $HOST -gpath $wgpath $path";
	ask_shell($cmd);
    }
    $cmd="$ct unlock vob:$vob";
    ask_shell($cmd);
    $cmd="$ct mount $vob";
    ask_shell($cmd);
     
    exit;
}

#
# Unregisters view and viewtag, leaves vob data intact
#
sub unreg_vob {
    my $vtag = shift;
    my $cmd;
    if (! defined $vtag ) {
	if ( ask_yn "No vobtag given, do you want to unregister all vobs?" ) {
	    $vtag="*alla*";
	} else {
	    msg "Aborted";
	    exit;
	}
    }
    debug("unreg_vob: $vtag");

    my $pass="";
    $pass="-password $RGYPASS" if $YES;

    foreach my $tag (keys %vobs) {
	if (( $tag eq $vtag) or ($vtag eq "*alla*")) {
	    my $vob = $vobs{$tag}{vob};
	    debug("unreg $vob");
	    save_vob($tag);
	    $cmd="$ct lock vob:$vob";
	    ask_shell($cmd);
	    $cmd="$ct umount $vob";
	    ask_shell($cmd,"warn");
	    $cmd="$ct rmtag $pass -vob -all $vob";
	    ask_shell($cmd);
	    $cmd="$ct unregister -vob ".escpath($vobs{$tag}{gpath});
	    ask_shell($cmd);
	    ### find server proecess and kill it
	    $cmd="ps -ef |grep -v grep| grep vob_server| grep $vtag| awk '{print \$2}'";
	    my $out=`$cmd`; chomp($out);
	    $cmd="kill $out";
            if ( $out ne "" ) {
               msg "Found vob_server process for $vob";
	       ask_shell($cmd);
            }
	    
	}
    }

}

#
# Upgrade feature level
#
sub chflevel {
    my $tag = shift;
    my $flevel = shift;
    my ($cmd,$err);
    my $vob=$vobs{$tag}{vob};
    error("Missing vobtag, usage: $0 -chflevel $flevel <vobtag>") if ! defined $vob;
    debug("chflevel: $vob $flevel");
    error("Unknow flevel") if ! defined $vobs{$tag}{flevel};

    error "Current chflevel is $vobs{$tag}{flevel}, no need to raise." if ( $flevel <= $vobs{$tag}{flevel} );
    msg "Current chflevel is $vobs{$tag}{flevel}" if ( $flevel >= $vobs{$tag}{flevel} );
    save_vob($tag);

    $cmd="$ct pwv | grep 'Set view:'| awk '{print \$3}'";
    debug($cmd);
    my $out = `$cmd`; chomp($out);
    error("No current view, set a view with 'cleartool setview vobadm'") if ( $out =~/NONE/);
    debug("current view: $out");

    chdir "$vob" or error("can't chdir to $vob");

    $cmd="$ct lsreplica|grep replica|grep -v \"For VOB\" |awk '{ print \$4 }' | tr -d \\\" ";
    debug($cmd);
    my $replica = `$cmd`; chomp($replica);
    debug("replica=$replica");

    $cmd="$ct chflevel -replica 5 replica:".$replica.'@'.$vob;
    ask_shell($cmd);
    $cmd="$ct chflevel -family 5 vob:$vob";
    ask_shell($cmd);
}

init_vobs() if $INIT;

read_vobs($vobsfile);

save_vob($VOBTAG) if $SAVE;
show_vob($VOBTAG) if $SHOW;
find_uuid($FINDVIEW) if $FINDVIEW;
chflevel($VOBTAG,$CHFLEVEL) if $CHFLEVEL;
restore_vob($VOBTAG) if $RESTORE or $REPLACE;
unreg_vob($VOBTAG) if $UNREG;
new_vob($VOBTAG) if $NEW;

list_vobs() if $LIST;

msg("OBS! You MUST restart the clearcase server after unregistering a vob!") if $UNREG
