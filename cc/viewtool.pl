#!/usr/bin/perl -w
#
# viewtool.pl
# by hakan.isaksson@init.se, 2012
#
# Count days from today and report age of ClearCase views
# pipe the output to "sort -n" to sort by age
#
# in this script swedish characters are coded with UTF-8
# in mail swedish characters are coded with sv.iso5589-1
#
# Works on view-servers on unix and windows(cygwin)
#
use strict;
use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;
use File::Basename;
use Date::Calc qw/:all/;
use Data::Dumper;
use Net::SMTP;
use POSIX;
use Encode qw(encode decode);
use utf8;

=pod

=head1 NAME

 viewtool.pl

=head1 SYNOPSIS

viewtool.pl [--help] [<options>] <viewtag>

=head1 OPTIONS

=over 10

=item B<--active>

Show only currently active views, i.e. views that would be displayed with a "*" if using cleartool lsview.

=item B<--age> <days>

Only show views older than -age <days> ago. Valid numbers are -1 to N.

=item B<--copy>

Copy view to backupdir before removing, only used with --remove

=item B<--debug>

Debug mode.

=item B<--delimiter>

Change delimiter character between fields with --list. Default is space.

=item B<--fields> <fields>

Select fields to show with --list
Default "age,tag,gpath"
Possible fields:
"age,last,tag,region,gpath,hpath,uuid,active,host,owner,type,created,createdby,modified"

=item B<--force> 

Ignore errors from cleartool that can halt this script.
Used to unregister a view that has missing storage location.

=item B<--help>

Show help.

=item B<--host> <server host>

Only views matching this host will be listed with B<--list>.
By default host is set to the host running this script,
it can be overridden with this option.
Use B<--host>="*" for any host.

=item B<--init>

Gather and save view information.
Runs "cleartool lsview -l -age "
This might take a long time, that's why the result is cached until the script is run again with this option.
The result is saved in a textfile under the viewtool.save directory.

=item B<--mailaddr> <addrfile>

CSV formatted list of usernames and email addresses. Format: "username","emailaddr"

=item B<--mailmsg> <msgfile>

Message body for mail reminders. Can contain tags that will be replaced for every message sent.
{{views}} is replaced by the persons view(s).
{{user}} is replaced by the persons userid.
{{mail}} is replaced by the persons mailaddr.
{{show_age}} is replaced by the value used with --age.

=item B<--mailreminder>

Send mail reminder to people with views.

=item B<--mailsubject> <subject>

Set mail subject. Overrides Subject: if it is set in the message body.

=item B<--mailto> <user>

Only mail this user. Used for testing.

=item B<--man>

Show man page, more verbose than --help.

=item B<--nosave>

Don't automatically save view information, useful when dealing with a damaged view that can't be saved.

=item B<--list>

List views.

=item B<--old> <nr>

Show a previously saved list of views. The lists are rotated, the most recent is
always 1, then 2 and so on up to the max keep limit. Only used with --list.

=item B<--region> <region>

Can be used to list views from another region than the default. Note that the views for that region must first 
be save with "-i --region region" prior to listing. Also changes the default listing fields and host.
View age and other information that requires access to the viewstorage will not be saved for this region,
this script assumes that is not possible, i.e. if you ha a unix and a windows region.

=item B<--remove> <viewtag>

Delete a view completely with cleartool rmview. Saves view info, use with --copy to save a complete backup.

=item B<--restore> <viewtag>

Restore a clearcase view, the view-info must have been saved by this tool.

=item B<--save> <viewtag>

Save viewinfo, to only save viewinfo without doing anything else.
Viewinfo is saved by automatically when doing --remove or --unregister.

=item B<--test>

Testmode. No changes are made.

=item B<--unregister> <viewtag>

Removes a view by unregistering and deleting the viewtag.
The actual view-files are left as they are.
Saves viewdescription to a file that can be used for --restore

=item B<--yes>

Answer yes to all questions.

=back

=head1 DESCRIPTION

viewtool.pl is an advanced tool for listing and manipulating ClearCase views.
Primarily it can be used to list views and show view age,

Can help to remove views (and helps by saving important data for restore) and restore views.

This script is designed to work on both unix and windows (with cygwin). 
It's best to run on a vob- or view- server as the clearcase administrator.

It will compose the appropriate cleartool commands and will ask before executing
anything that may change the system.

Because gathering this information about alla view can be timeconsuming, 
the data is always cashed and is only renewed by request.

All cached data and backups are stored in the directory ./viewtool.save in the same dir as this script.
Ther is also an options.txt file with default vales.

=head1 EXAMPLES

Create or update view list:
viewtool.pl -i

List all views older than one year:
viewtool.pl -l --host="*" --age 365 --fields="age,tag"

Save and list another region:
viewtool.pl -i -l --region windows_region

Unregister a view:
viewtool.pl --unreg test_view2

Delete a view and answer all questions with yes:
viewtool.pl --remove test_view2 -y

Restore a unregistered or removed view:
viewtool.pl --restore test_view2

Send mail reminder to all users with views old than 180 days.
viewtool.pl --mailremind -age=180 -y

=cut

my $DEBUG=0;        ### Debugmode
my $TEST=0;         ### Testmode
my $SHOW_AGE=0;     ### Only show views older than this date
my $COPY=0;         ### Backup view before remove
my $LIST=0;         ### List views
my $INIT=0;         ### Init age input file
my $UNREG=0;        ### Remove viewtag
my $RESTORE=0;      ### Restore viewtag
my $REMOVE=0;       ### Delete viewdata
my $SAVE=0;         ### Save view description
my $NOSAVE=0;       ### Don't save view description
my $SHOW=0;         ### Show saved view description
my $YES=0;          ### answer 'yes' to all questions 
my $FORCE=0;        ### Ignore some errors
my $REMIND=0;       ### Send mail reminder to view owners
my $REGION="";      ### Change region (defaults to current region)
my $OLD=0;          ### Show old list
my $TERM;           ### Terminal type, unix or cygwin or dos (windows without cygwin)

my $DELIMITER;      ### Field delimiter
my $FIELDS;         ### List fields

my $KEEP=20;        ### Number of old list versions to keep
my $HOST;           ### Server host (only show views registered to this server host)
my $SAVEDIR;

my $ct="cleartool";

my ($viewsfile,$optsfile,$logfile);
my ($SMTPSERVER,$MAILFROM,$CHARSET,$MAILADDRS,$MAILMSG,$SUBJECT,$MAILTO);

my %views;

GetOptions(
    
    "age=s"      => \$SHOW_AGE,
    "copy"       => \$COPY,
    "d|debug+"   => \$DEBUG,
    "delimiter=s"=> \$DELIMITER,
    "f|force"    => \$FORCE,
    "fields=s"   => \$FIELDS,
    "host=s"     => \$HOST,
    "list"       => \$LIST,
    "i|init+"    => \$INIT,
    "mailaddr=s" => \$MAILADDRS,
    "mailfrom=s" => \$MAILFROM,
    "mailmsg=s"  => \$MAILMSG,
    "mailremind" => \$REMIND,
    "mailsubject=s" => \$SUBJECT,
    "mailto=s"   => \$MAILTO,
    "nosave"     => \$NOSAVE,
    "old=s"      => \$OLD,
    "region=s"   => \$REGION,
    "remove"     => \$REMOVE,
    "restore"    => \$RESTORE,
    "save"       => \$SAVE,
    "s|show"     => \$SHOW,
    "test"       => \$TEST,
    "unregister" => \$UNREG,
    "yes"        => \$YES,
    "h|help"     => sub {pod2usage(-verbose => 1)},
    "man"        => sub {pod2usage(-verbose => 2)},
    ) || pod2usage();

my $VIEWTAG = $ARGV[0];
$TERM=detect_cygwin();

$SAVEDIR="".dirname($0)."/viewtool.save";
$SAVEDIR=File::Spec->rel2abs($SAVEDIR);

$viewsfile=$SAVEDIR."/views.txt";
$optsfile=$SAVEDIR."/options.txt";
$logfile=$SAVEDIR."/log.txt";
read_opts($optsfile);

if ($REGION ne "") {
    $viewsfile=$SAVEDIR."/$REGION.views.txt";
    $SHOW_AGE=-1;
    $HOST="*" if ! defined $HOST;
    $FIELDS="region,tag,hpath" if ! defined $FIELDS;
}
$HOST="*" if ! defined $HOST;                  ### List views from all hosts by default
$FIELDS="age,tag,gpath" if ! defined $FIELDS;  ### Default List fields
$DELIMITER=" " if ! defined $DELIMITER;        ### Default delimiter
$CHARSET='latin1' if ! defined $CHARSET;       ### Default mail charset
$MAILADDRS=$SAVEDIR."/epostadresser.csv" if ! defined $MAILADDRS;     ### Default MAILADDRS
$MAILADDRS=$SAVEDIR."/".$MAILADDRS if substr($MAILADDRS,0,1) ne "/";   
$MAILMSG="mailmsg.txt" if ! defined $MAILMSG;                         ### Default MAILMSG
$MAILMSG=$SAVEDIR."/".$MAILMSG if substr($MAILMSG,0,1) ne "/";        
$SUBJECT="" if ! defined $SUBJECT;

#$/ = "\r\n" if $TERM eq "cygwin";

debug("TEST=$TEST") if $TEST;
debug("TERM=$TERM");
debug("CHARSET=$CHARSET");
debug("VIEWTAG=$VIEWTAG") if defined $VIEWTAG;
debug("HOST=$HOST");
debug("SHOW_AGE=$SHOW_AGE");
debug("SAVEDIR=$SAVEDIR");
debug("DELIMITER=<$DELIMITER>");
debug("FIELDS=$FIELDS");
debug("MAILREMIND=$REMIND") if $REMIND ge 1;
debug("SMTPSERVER=$SMTPSERVER") if defined $SMTPSERVER;
debug("MAILFROM=$MAILFROM") if defined $MAILFROM;
debug("MAILTO=$MAILTO") if defined $MAILTO;
debug("MAILMSG=$MAILMSG") if defined $MAILMSG;
debug("MAILADDRS=$MAILADDRS") if defined $MAILADDRS;

error("Missing viewtag to --remove") if ! defined $VIEWTAG and $REMOVE;
pod2usage(-verbose => 1) if ! defined $VIEWTAG and ((! $LIST)and (!$INIT) and(!$REMIND));

msg("WARNING: Incompatible environment, run on unix or in cygwin in windows") if (($TERM ne "cygwin")and($TERM ne "unix"));

sub msg {
    my $msg = shift(@_);
    printf "$msg\n";
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
    #my $out = qx/uname/;
    #chomp($out);
    my $os = $^O;
    if ($os =~ /cygwin/) {
	$type="cygwin";
    } elsif ($os =~ /MSWin32/) {
	$type="dos";
    } else {
	$type="unix";
    }
    return $type;
}

sub cygpath {
    my $path=shift;
    my $out;
    if ($TERM eq "cygwin") {
	$out=`cygpath -w $path`;
	chomp($out);
    } else {
	$out=$path;
    }
    return $out;
}
sub escpath {
    my $path=shift;
    if ($TERM eq "cygwin") {
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
# Read options and define variables unless they have already been set by arguments
#
sub read_opts {
    my $file = shift;
    debug("read_opts: loading $file");

    if ( open(F,"<$file") ) {
        binmode(F);
        while (<F>) {
            chomp;
            if (/^(\w*)\=([\w\:\.\\\/\-\_,@]*)/) {
                my ($var,$val) = ($1,$2);
                $val=~ s/\\/\\\\/g;  
                eval("\$$var=\'$val\' if ! defined \$$var;");
                debug("read_opts: \$$var=\'$val\' if ! defined \$$var;",2);
            }
        }
        close(F);
    } else {
        msg("WARNING: Can't open $file: $!\nCreate $file and define the following variables: SMTPSERVER,MAILFROM,MAILADDRS");
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
	    shell("mv $of ${old}${new}${gz}") if $TERM ne "dos";
	    shell("move $of ${old}${new}${gz}") if $TERM eq "dos";
	}
    }
}

#
# Read the $viewsfile created with --init
#
sub read_views {
    my $file = shift;
    debug("read_views: $file");
    my $tag="";
    my ($y,$m,$d)= Today();
    my $now = sprintf("%4d-%02d-%02d",$y,$m,$d);
    debug("now=$now");
    $file=$SAVEDIR."/views.txt.$OLD" if $OLD > 0;
    $file=$SAVEDIR."/$REGION.views.txt.$OLD" if $OLD > 0 and $REGION ne "";
    debug("read_views: open $file",2);
    open(F,"<$file") or error ("can't open $file: $!\nRun $0 --init to create $file.");
    binmode(F);
    while (<F>) {
	chomp;
	$_ =~s/\r//g;
	#$tag=$1,$views{$tag}{tag}=$tag if /^Tag:\s(.+)/;
	if (/^Tag:\s+([\\\w\-\.\$åäö]+)/) {
	    $tag=$1;$views{$tag}{tag}=$tag;
            debug("read_views: found tag=$tag",2);
	}
	$views{$tag}{gpath}=$1 if /\s+Global path:\s(.+)/;
	$views{$tag}{region}=$1 if /\s+Region:\s(.+)/;
	$views{$tag}{host}=$1 if /\s+Server host:\s(.+)/;
	$views{$tag}{uuid}=$1 if /^View uuid:\s(.+)/;
	$views{$tag}{active}=$1 if /\s+Active:\s(.+)/;
	$views{$tag}{hpath}=$1 if /^View server access path:\s(.+)/;
	$views{$tag}{type}=$1 if /^View attributes:\s(.+)/;
	#$views{$tag}{owner}=$1 if /^View owner:\s(.+)/;
	if (/^View owner:\s(.+)/) {
	    $views{$tag}{owner}=$1;
	    my @info = split(/\\/,$views{$tag}{owner});
	    $views{$tag}{user}=$info[1];
            $views{$tag}{user}=$views{$tag}{owner} if ! defined $views{$tag}{user};
	}
	if (/Created\s(\d+)\-(\d+)-(\d+).* by .*@(.*)/) {
	    $views{$tag}{'created'}="$1-$2-$3";
            $views{$tag}{'createdby'}=$4;
	}
	if (/Last modified\s(\d+)\-(\d+)-(\d+)/) {
	    $views{$tag}{'modified'}="$1-$2-$3";
	}
	if (/Last\saccessed\s(\d+)\-(\d+)-(\d+)/) {
            my $last="$1-$2-$3";
            my $days = Delta_Days($1,$2,$3, $y,$m,$d);
            my $pdays = sprintf("%05d", $days);
	    $views{$tag}{'age'}=$pdays;
	    $views{$tag}{'last'}=$last;
	}
    }
    close(F);

    foreach my $key (keys %views) {
	$views{$key}{type}="dynamic" if ! defined $views{$key}{type};
	$views{$key}{age}=-1 if ! defined $views{$key}{age};
    }
    debug("read_views: loaded ".scalar(keys %views)." views.");

    print Dumper(\%views) if $DEBUG ge 3;

}

#
# Save long descripton for specific view
#
sub save_view {
    my $view=shift;
    debug("save_view: $view");
    error("view not found: $view") if ! defined $views{$view}{tag};
    my $descfile = $SAVEDIR."/lsview.".$view.".txt";
    rotate_file($descfile, $KEEP);
    my $cmd="$ct lsview -long -properties $view > $descfile";
    my $err = shell($cmd);
    if ($err and !$FORCE) {
	shell("rm $descfile");
	error("Failed cmd: $cmd");
    }
    debug("save_view: created $descfile",2);
}

#
# Save a list of all views with -long description to $viewsfile
#
sub init_views {
    debug("init_views");
    my $err=0;
    my $cmd="mkdir -p $SAVEDIR";
    $err=shell($cmd) if ! -d $SAVEDIR;
    error("Failed cmd: $cmd") if $err;

    $cmd="$ct lsview -l -properties > $viewsfile";
    $cmd="$ct lsview -l -region $REGION > $viewsfile" if ($REGION ne "");
    rotate_file($viewsfile, $KEEP);

    msg("Gathering view information, this may take a long time..");
    msg("$cmd");
    $err=shell($cmd);
    if ($err) {
        #shell("rm $viewsfile");
        msg("cleartool returned error: $cmd");
    }
}

#
# Load or Show saved description of specific view
#
sub show_view {
    my $view=shift;
    debug("show_view: $view");
    my $descfile = $SAVEDIR."/lsview.".$view.".txt";
    open(F,"<$descfile") or error("Can't open $descfile: $!");
    binmode(F);
    while (<F>) {
	chomp;
	$_ =~s/\r//g;
	msg($_) if ! $RESTORE;
	### load view for restore_view
        $views{$view}{tag}=$1 if /^Tag:\s(.+)/;
        $views{$view}{gpath}=$1 if /\s+Global path:\s(.+)/;
        $views{$view}{region}=$1 if /\s+Region:\s(.+)/;
        $views{$view}{host}=$1 if /\s+Server host:\s(.+)/;
        $views{$view}{uuid}=$1 if /^View uuid:\s(.+)/;
        $views{$view}{active}=$1 if /\s+Active:\s(.+)/;
        $views{$view}{hpath}=$1 if /^View server access path:\s(.+)/;
        $views{$view}{owner}=$1 if /^View owner:\s(.+)/;
        $views{$view}{type}=$1 if /^View attributes:\s(.+)/;
    }
    close(F);

    exit if ! $RESTORE;
}

#
# Unregisters view and viewtag, leaves view data intact
#
sub unreg_view {
    my $view=shift;
    debug("unreg_view: $view");
    my ($cmd,$err);

    error("view not found: $view") if ! defined $views{$view}{tag};
    save_view($view) if $NOSAVE ne 1;

    $cmd="$ct endview $view" ;
#    shell($cmd) if $views{$view}{active} ne "NO";
    if (ask_yn("$cmd")) {
	shell($cmd);
    }

    my $done=0;
    my $gpath=escpath($views{$view}{gpath});
    $cmd="$ct unregister -view -uuid ".$views{$view}{uuid};
    if (ask_yn("$cmd")) {
	$err=shell($cmd);
	error("Failed cmd: $cmd") if $err;
	logmsg($cmd);
	$done++;
    }

    $cmd="$ct rmtag -view $view";
    if (ask_yn("$cmd")) {
	$err=shell($cmd);
	error("Failed cmd: $cmd") if $err;
	logmsg($cmd);
	$done++;
    }
    logmsg("unregistered view $gpath uuid $views{$view}{uuid}") if $done;
    exit;
}

#
# rmview
#
sub remove_view {
    my $view=shift;
    my ($cmd,$err);
    debug("remove_view: $view");
    error("view not found: $view") if ! defined $views{$view}{tag};

    my $hpath=escpath($views{$view}{hpath});
    my $savepath;
    if ( $TERM eq "unix") {
	error("You don't have permission to remove $hpath, try as root?") if ! -o $hpath and $< ne 0;
    }

    save_view($view) if $NOSAVE ne 1;
    $cmd="$ct endview $view" ;
    shell($cmd) if (ask_yn("$cmd"));
    
    if ( $COPY ) {
	$savepath="$SAVEDIR/${view}.vws" if ( $TERM eq "cygwin");
	$savepath="$SAVEDIR/${view}.vws.tar" if ( $TERM eq "unix");

	if ( -e $savepath ) {
	    msg "WARNING: Savepath $savepath already exists!";
	} else {
	    if ( $TERM eq "cygwin") {
		$savepath=escpath(cygpath($savepath));
		#$cmd="xcopy /E /H /K /O /X /I $hpath $savepath";
		$cmd="xcopy /E /H /K /I $hpath $savepath";
		if (ask_yn("$cmd")) {
		    error("Failed cmd: $cmd") if shell($cmd) ne 0;
		}
	    }
	    if ( $TERM eq "unix") {
		$cmd="tar cf $savepath $hpath";
		if (ask_yn("$cmd")) {
                    $err=shell($cmd);
		    shell("rm -f $savepath") if $err;
                    error("Failed cmd: $cmd") if $err;
		    $cmd="gzip $savepath";
		    shell($cmd) if ask_yn($cmd);
                }
	    }
	    if ( $TERM eq "dos") {
		error "--copy not implemented for $TERM.";
	    }
	}
    }
    my $done=0;

    #$cmd="$ct rmview -tag ".$view;
    $cmd="$ct rmview -force ".escpath($views{$view}{gpath});
    if (ask_yn("$cmd")) {
	$err = shell($cmd);
	error("Failed cmd: $cmd") if $err;
	logmsg($cmd);
	$done++;
    }
    logmsg("removed view uuid $views{$view}{uuid}") if $done;
    exit;
}

#
# register and mktag
#
sub restore_view {
    my $view=shift;
    my ($cmd,$err);
    
    debug("restore_view: $view");
    show_view($view);

    my $path=escpath($views{$view}{hpath});
    my $gpath=escpath($views{$view}{gpath});
    error("$view hpath unknown") if ! defined $path;

    my $savepath;
    if (! -d  $path ) {
	msg "View storage not found: $path";
	$savepath="$SAVEDIR/${view}.vws" if ( $TERM eq "cygwin");
	$savepath="$SAVEDIR/${view}.vws.tar.gz" if ( $TERM eq "unix");
	debug("savepath=$savepath");
	if ( -e "$savepath" ) {
	    if ($TERM eq "cygwin") {
		$savepath=escpath(cygpath($savepath));
		my $hpath=escpath(cygpath($path));
		msg "Restore view data from $savepath?";
		$cmd="xcopy /E /H /K /O /X /I $savepath $hpath";
		if ( ask_yn($cmd) ) {
		    error("Failed cmd: $cmd") if shell($cmd);
		}
	    }
	    if ( $TERM eq "unix") {
		msg "Restore view data from $savepath?";
		$cmd="gunzip -c $savepath| tar xvpf -";
		if ( ask_yn($cmd) ) {
                    $err=shell($cmd);
                    error("Failed cmd: $cmd") if $err;
                }
	    }
	} else {
	    error("Can't restore view: $view");
	}
    }
    $cmd="$ct register -view -host ".$views{$view}{host}." -hpath ".$path." ".$gpath;
    if (ask_yn("$cmd")) {
	$err=shell($cmd);
	error("Failed cmd: $cmd") if $err;
	logmsg($cmd);
    }
    $cmd="$ct mktag -view -tag $view -host ".$views{$view}{host}." -gpath ".$gpath." ".$path;
    if (ask_yn($cmd)) {
	$err = shell($cmd);
	error("Failed cmd: $cmd") if $err;
	logmsg($cmd);
    }
    exit;
}

#
# List selected view fields and sort output
#
sub list_views {
    #debug("list_views:");
    my @out;
    my $tot=0;
    foreach my $tag (keys %views) {
	$tot++;
	my $str="";
	if ($views{$tag}{age} >= $SHOW_AGE) { 

	    my @fields = split(/,/,$FIELDS);
	    foreach my $f (@fields) {
		$str.=$views{$tag}{$f}.$DELIMITER;
	    }
	    if ($HOST ne "*") {
		push(@out, $str) if uc($views{$tag}{host}) eq uc($HOST);
	    } else {
		push(@out, $str);
	    }
	} else {
	    debug("list_views: SKIP $tag: age=$views{$tag}{age} ") if ! $REMIND;
	}
    }

    foreach my $s (sort(@out)) {
	msg $s if ! $REMIND;
    }
    debug("list_views: ".scalar($#out)."/$tot views matched.");
    return \@out;
}

sub load_mailaddr {
    my $addrfile = shift;
    my %maddr;
    debug("load_mailaddr: loading $addrfile");
    open(F,"<$addrfile") or error ("can't open $addrfile: $!\nExpects a csv formated file named $addrfile with email adresses.");
    binmode(F);
    while (<F>) {
        chomp;
        s/\r//;
        s/\"//g;
        my ($cn,$m) = split(/,/);
        debug("READ $addrfile: $cn $m",4);
        $maddr{$cn}{mail}=$m if (defined $m) and ($m ne "");
    }
    debug("load_mailaddr: loaded ".scalar(keys %maddr)." adresses.");

    return %maddr;
}

sub load_msgfile {
    my $msgfile = shift;
    my @data = ( "\n" );
    debug("load_msgfile: loading $msgfile");
    open(F,"<$msgfile") or error ("can't open $msgfile: $!\nExpects a textfile with the mail body.");
    binmode(F);
    while (<F>) {
        chomp;
        s/\r//g;
	my $l = $_;
	if (/Subject:\s*(.+)/) {
	    $SUBJECT=$1;
	} else {
	    push(@data, $l);
	}
        debug("READ $msgfile: $_",3);
    }
    close(F);
    debug("load_msgfile: loaded ".scalar(@data)." lines.");
    return [ @data ];
}

#
# Replace tags in msg body
#
sub replace_data {
    my $data = shift;
    my $rep = shift;
    my $id = shift;
    debug("replace_data (user=$id)",3);
    #print "rep = ".Dumper($rep) if $DEBUG ge 3;
    #print "data = ".Dumper($data) if $DEBUG ge 3;
    my $fl = "tag,mail";
    my @fields = split(/,/,$fl);
    my $nf=$fields[0];
    for my $l (@{ $data }) {
        for my $fn (@fields) {
            my $fv; 
	    if ( defined $rep->{$id}{$fn} ) {
		$fv = $rep->{$id}{$fn};
		$l =~ s/\{\{$fn\}\}/$fv/;
		$l =~ s/\{\{user\}\}/$id/;
		$l =~ s/\{\{show_age\}\}/$SHOW_AGE/;
		if ($l =~ /\{\{views\}\}/) {
		    my $vstr="";
		    foreach my $tag (@{ $rep->{$id}{views} }) {
			$vstr.="  $tag\n";
		    }
		    $l =~ s/\{\{views\}\}/$vstr/;
		    
		}
	    }
        }
        debug("replace_data: $l",3);
    }
    #print Dumper($data);
}

#
# Send reminder to view owners
#
sub mail_remind {
    my $file = shift;
    debug("mail_remind:");

    # load mailaddrs
    my %maddr = load_mailaddr( $file);
     
    ### find views
    $FIELDS="tag,age,user";
    my $out = list_views();
    foreach my $s (sort(@{$out})) {
	my ($tag, $age, $uid) = split(/\s/,$s);
	#my ($uid, $rest) = split(/_/,$tag);
	#debug("try $uid",3);
	if (defined($maddr{$uid}{mail})) {
	    debug("mail_remind: $tag: mailaddr found for $uid = $maddr{$uid}{mail}",2);
	    push( @{ $maddr{$uid}{views} }, $tag);
	} else {
	    debug("mail_remind: $tag: No mailaddr for $uid",2);
	}
    }

    ### Compose and send message
    foreach my $u (keys %maddr) {
	next if ((defined $MAILTO) and ($u ne $MAILTO));  ### debug
	if (defined $maddr{$u}{views}) {
	    my ($name, $rest) = split(/\@/,$maddr{$u}{mail});
	    $name =~ s/\./\ /g;
	    $name =~ s/\b(\w)/\U$1/g;
	    $maddr{$u}{name}=$name;

	    my @data = @{ load_msgfile($MAILMSG) };
	    error("SUBJECT is empty") if $SUBJECT eq "";

	    my @s = ( $SUBJECT );  replace_data(\@s,\%maddr,$u); $SUBJECT = pop(@s);
	    replace_data(\@data,\%maddr,$u);

	    sendmail($SMTPSERVER,$MAILFROM,$maddr{$u}{mail},$SUBJECT,@data);
	} else {
	    debug("mail_remind: $u has no views",2);
	}
    }
}

#
# Send mail with SMTP
#
sub sendmail {
    my ($smtpserver) = shift(@_);
    my ($from) = shift(@_);
    my ($mailto) = shift(@_);
    my ($subject) = shift(@_);
    my @data = @_;
    my $smtp;

    ### assumes this script is coded in UTF-8
    $subject = encode($CHARSET, decode('utf-8', $subject));

    debug("sendmail: $smtpserver,$from,$mailto,$subject");
    
    debug("TEST: SKIP mail to $mailto"),return if $TEST;
    my $a=$YES;
    $a = ask_yn("Send mail to $mailto?") if ! $YES;
    debug("SKIP mail to $mailto"),return if ! $a;

    if ($#data > -1) {
    $smtp = Net::SMTP->new($smtpserver, Timeout => 30 )
	or die("Can't connect to $smtpserver\n");

    $smtp->mail($from);
    $smtp->to($mailto);

    $smtp->data();
    $smtp->datasend("To: $mailto\n");
    $smtp->datasend("Subject: $subject\n");
    foreach my $d (@data) {
        #debug("sendmail: DATA $d",3);
	$smtp->datasend( encode($CHARSET, decode('utf-8', $d))."\n" );
    }
    $smtp->dataend();
    $smtp->quit;
    }
}


#
# Main
#

init_views() if $INIT;

read_views($viewsfile);

save_view($VIEWTAG) if $SAVE;
show_view($VIEWTAG) if $SHOW;
restore_view($VIEWTAG) if $RESTORE;
remove_view($VIEWTAG) if $REMOVE;
unreg_view($VIEWTAG) if $UNREG;

list_views() if $LIST;
mail_remind($MAILADDRS) if $REMIND;

