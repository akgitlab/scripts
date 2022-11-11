#!/usr/bin/perl
use DBI;
use File::Path qw(mkpath);
use File::Basename;
use constant false => 0;
use constant true  => 1;
my %config;
my $dbh;

# If you want to run the tool in batch mode to process recordings that were not processed before, you can use a bash command like the following one.
# Be sure to su to the asterisk user before running it.
#
#for A in /var/spool/asterisk/monitor/q*; do fecha=`date +%Y-%m-%d -r $A`; unique=${A#*-}; uniqueid=${unique%.*}; echo "/usr/local/parselog/update_mix_mixmonitor_date.pl $uniqueid /var/spool/asterisk/monitor/$A $fecha"; done
#
# This other one liner is for FreePBX 12 or higher
#
# for A in `find /var/spool/asterisk/monitor/2016/ -name q\*`;do unique=${A#*-}; unique=${unique#*-};unique=${unique#*-};unique=${unique#*-};unique=${unique#*-};uniqueid=${unique%.*}; echo "/usr/local/parselog/update_mix_mixmonitor.pl $uniqueid $A"; done
#
# And this one if you convert to mp3 or move the file over, so date is preserved
#
# for A in `find /var/spool/asterisk/monitor/2016/ -name q\*`; do unique=${A#*-}; unique=${unique#*-}; unique=${unique#*-}; fecha=$unique anio=${fecha:0:4}; mes=${fecha:4:2}; dia=${fecha:6:2}; unique=${unique#*-}; unique=${unique#*-}; uniqueid=${unique%.*}; echo "/usr/local/parselog/update_mix_mixmonitor.pl $uniqueid $A $anio-$mes-$dia"; done
# Output from above should be captured to file so you can review if its valid, and then run that file as a shell script


# Main configuration
# You have to set the proper database credentials
$config{'dbhost'} = 'localhost';
$config{'dbname'} = 'qstats';
$config{'dbuser'} = 'qstatsUser';
$config{'dbpass'} = 'qstatsPassw0rd';

# Temporary destination directory for converted to .mp3 recordings
$config{'asterisk_spool'}  = "/var/spool/asterisk/monitor";
$config{'destination_dir'} = "/var/spool/asterisk/outgoing";

# If you want to move the original asterisk recording to a new path
# Not really needed unless you want to perform file convertion to mp3 or similar
$config{'move_recording'} = true;

# If you want "wav" recordings to be converted to .mp3 
# It requires the lame tool to be installed. You also must
# configure move_recordings above to true, as the mp3 file
# will be stored in a different path than asterisk defaults (destination_dir)
$config{'convertmp3'} = true;

# Do not modify bellow this line
# ---------------------------------------------------------------------------
my $res = &connect_db();

if($res) {

    my $DBHOST='';
    my $DBUSER='';
    my $DBPASS='';
    my $DBNAME='';

    if( -f '/var/www/html/reports/config.php') {
         open(my $fh, "<", '/var/www/html/reports/config.php') or die "Can't open < /var/www/html/reports/config.php: $!";
         while (my $row = <$fh>) {
             chomp $row;
             if($row =~ m/\$DB/) {
                 eval $row;
             }
         }
         close $fh;
    }

    if( -f '/var/www/html/stats/config.php') {
         open(my $fh, "<", '/var/www/html/stats/config.php') or die "Can't open < /var/www/html/stats/config.php: $!";
         while (my $row = <$fh>) {
             chomp $row;
             if($row =~ m/\$DB/) {
                 eval $row;
             }
         }
         close $fh;
    }

    if ($DBHOST ne '') {
        $config{'dbhost'} = $DBHOST;
    }

    if ($DBUSER ne '') {
        $config{'dbuser'} = $DBUSER;
    }

    if ($DBPASS ne '') {
        $config{'dbpass'} = $DBPASS;
    }

    if ($DBNAME ne '') {
        $config{'dbname'} = $DBNAME;
    }

    $res = &connect_db();
}

if($res) {
    print "Cannot connect to MySQL server ".$config{'dbhost'}.", to database ".$config{'dbname'}.". using user ".$config{'dbuser'}." and secret ".$config{'dbpass'}."\n";
    exit;
}

my $LAME = `which lame 2>/dev/null`;
chomp($LAME);

sub connect_db() {
    my $return = 0;
    my %attr = (
        PrintError => 0,
        RaiseError => 0,
    );
    my $dsn = "DBI:mysql:database=$config{'dbname'};host=$config{'dbhost'}";
    $dbh->disconnect if $dbh;
    $dbh = DBI->connect( $dsn, $config{'dbuser'}, $config{'dbpass'}, \%attr ) or $return = 1;
    return $return;
}

sub read_config() {
    my $has_move=0;
    my $has_convert=0;
    my $has_destination=0;
    $query = "SELECT keyword,parameter,value FROM setup WHERE keyword like 'recording%'";
    $sth = $dbh->prepare($query);
    $sth->execute();
    my @row;
    while (@row = $sth->fetchrow_array) {
        my $keyword   = $row[0];
        my $parameter = $row[1];
        my $value     = $row[2];
        if($keyword eq "recordings_move") {
            $has_move=1;
            if($value==1 || $value eq "on" || $value eq "true") {    
                $config{'move_recording'} = true;
            } else {
                $config{'move_recording'} = false;
            }
        } elsif($keyword eq "recordings_asterisk_spool") {
            $config{'asterisk_spool'}  = $value;
        } elsif($keyword eq "recordings_move_destination") {
            $has_destination=1;
            $config{'destination_dir'} = $value;
        } elsif($keyword eq "recordings_convert_mp3") {
            $has_convert=1;
            if($value==1 || $value eq "on" || $value eq "true") {
                $config{'convertmp3'} = true;
            } else {
                $config{'convertmp3'} = false;
            }
        }
    }
    $sth->finish;

    if($has_move==0) {
        $query = "INSERT INTO setup (keyword,paramenter,value) VALUES ('recordings_move','',$config{'move_recording'})";
        $dbh->do($query);
    }
    if($has_convert==0) {
        $query = "INSERT INTO setup (keyword,parameter,value) VALUES ('recordings_convert_mp3','',$config{'convertmp3'})";
        $dbh->do($query);
    }
    if($has_destination=='') {
        $query = "INSERT INTO setup (keyword,parameter,value) VALUES ('recordings_move_destination','',?)";
        $sth = $dbh->prepare($query);
        $sth->execute( $config{'destination_dir'});
        $dbh->do($query);
    }

}

read_config();

my $uniqueid             = $ARGV[0];
my $original_sound_file  = $ARGV[1];
my $passeddate           = $ARGV[2];

if($uniqueid eq "") {
    print "No parameters specified. Aborting.\n";
    exit 1;
}

my $normalized_sound_file = $original_sound_file;

$normalized_sound_file     =~ s/wav49/WAV/g;

# We add the spool path to the original sound file
$normalized_sound_file     =~ s/$config{'asterisk_spool'}//g;
$normalized_sound_file     =~ s/^\///g;
$normalized_sound_file     = $config{'asterisk_spool'}."/".$normalized_sound_file;

# Extract filename and suffix for later processing
my($filename, $directories, $suffix) = fileparse($normalized_sound_file, "\.[^.]*");
$filename_nosuffix = $filename;
$filename = $filename.$suffix;
$filename_nosuffix =~ s/\+//g;
$filename =~ s/\+//g;

# Execute update_mix plugin files, files with extension .plugin with regular perl coode 
# that can inherit variables like $uniqueid, $original_sound_file, $passeddate, etc.
#
if ( -d '/usr/local/parselog/plugins' ) {
    opendir(DIR,"/usr/local/parselog/plugins");
    my @files = readdir(DIR);
    closedir(DIR);
    foreach my $file (@files) {
        next if $file =~ /^\.\.?$/;
        next if $file !~ /\.plugin$/;
        my $content;
        open(my $fh, '<', "/usr/local/parselog/plugins/$file") or warn "cannot open file $file"; {
            local $/;
            $content = <$fh>;
        }
        close($fh);
        eval $content; warn $@ if $@;
    }
}

if($config{'move_recording'} == true) {

    my $firstletter = substr $filename, 0, 1;
    if ($firstletter ne "q" && $firstletter ne "o" && $firstletter ne "i" ) { print "Skip processing because first letter is $firstletter\n"; exit; }

# Set subdate destination directory
    $time = localtime(time);
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    $datesubdir = sprintf ("%4d/%02d/%02d",$year+1900,$mon+1,$mday);

    if($passeddate ne "") {
        $datesubdir = $passeddate;
    }
    my $dest_directory     = $config{'destination_dir'}."/".$datesubdir;

# Create destination directory
    mkpath("$dest_directory");

# Set sql field
    $dest_sql           = $datesubdir."/".$filename;

    if($suffix eq ".wav" && $config{'convertmp3'} == true && $LAME ne "" && -f $LAME) {
# mp3 convertion if all conditions are met (config, lame installed, .wav file)
        my $file_mp3           = $filename_nosuffix.".mp3";
        my $dest_file_mp3      = $config{'destination_dir'}."/".$datesubdir."/".$file_mp3;
        my $temp_file_mp3      = $config{'asterisk_spool'}."/".$file_mp3;
        $dest_sql              = $datesubdir."/".$file_mp3;
        if ( -f $LAME ) {
            mkpath("$dest_directory");
            system("$LAME --silent -m m -b 8 --tt $normalized_sound_file --add-id3v2 $normalized_sound_file $temp_file_mp3");
            my $result = system("cp $temp_file_mp3 $dest_file_mp3");
            if($result==0) {
                system("rm -f $normalized_sound_file");
            }
            system("rm -f $temp_file_mp3");
        }
    } else {
# No convertion, just copy the file to destination directory
        my $dest_file_wav  = $config{'destination_dir'}."/".$datesubdir."/".$filename;
        my $result = system("cp $normalized_sound_file $dest_file_wav");
        if($result==0) {
            system("rm -f $normalized_sound_file");
        }
    }

} else {

# Use the standard file location as stored in newer systems like FreePBX>=12
    $datesubdir = sprintf ("%4d/%02d/%02d",$year+1900,$mon+1,$mday);
    $dest_directory = $directories; 

    $dest_directory     =~ s/$config{'asterisk_spool'}//g;
    $dest_directory     =~ s/^\///g;

    $dest_sql       = $dest_directory.$filename;

}

# check if there is a record with xfer uniqueid
$query = "SELECT uniqueid FROM queue_stats WHERE uniqueid='$uniqueid"."_xfer'";
$sth = $dbh->prepare($query);
$sth->execute();
my @resultxfer  = $sth->fetchrow_array;
my $cuantosxfer = @resultxfer;
$sth->finish;

# Update the DB
my $query = "INSERT INTO recordings VALUES('$uniqueid','$dest_sql') ON DUPLICATE KEY UPDATE filename='$dest_sql'";
$dbh->do($query);

if ($cuantosxfer) {
    my $query = "INSERT INTO recordings VALUES('$uniqueid"."_xfer','$dest_sql') ON DUPLICATE KEY UPDATE filename='$dest_sql'";
    $dbh->do($query);
}

# OPTIONAL - updating CDR and CEL tables when convert to MP3 is enabled - uncomment the following if block
#
# need to grant appropriate mysql perms to update recordingfile in asteriskcdrdb.cdr and cel.appdata
# grant update,insert,delete,select on `asteriskcdrdb`.`cdr` TO 'qstatsUser'@'localhost';
# grant update,insert,delete,select on `asteriskcdrdb`.`cel` TO 'qstatsUser'@'localhost';
#
# if ($suffix eq ".wav" && $config{'convertmp3'} == true) { 
#
#    my $recordingfile = $filename;
#    $recordingfile =~ s/\.wav$/.mp3/;
#
#    my $query = "UPDATE asteriskcdrdb.cdr SET recordingfile='$recordingfile' WHERE uniqueid='$uniqueid'";  # for CDR Reports
#    $dbh->do($query);
#
#    my $query = "UPDATE asteriskcdrdb.cel SET appdata=replace(appdata, '.wav', '.mp3') WHERE uniqueid='$uniqueid' AND appdata like '%mixmon%'"; # for UCP
#    $dbh->do($query);
#
#}

$dbh->disconnect if $dbh;
