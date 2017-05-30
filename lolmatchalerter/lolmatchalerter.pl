

use strict;
use warnings;
use Getopt::Long;
use Proc::Daemon;
use Cwd;
use File::Spec::Functions;
use LWP::UserAgent;
use Test::More;
use JSON::XS;
use Net::SMTP::SSL;
use Data::Dumper;
use Config::Simple;

#Constants and stuff
use constant RANKED => 4;
my $cfg = new Config::Simple();
$cfg->read('conf/sannie.conf');

my $API_Key = $cfg->param('API.key');
my $sender = $cfg->param('EMAIL.username');
my $password = $cfg->param('EMAIL.password');
my $platform = 'NA1';
my $ua = LWP::UserAgent->new;

my $summonerInfo;
my $time = time;
my $body = "Quickly, go watch ting! ";
my $subject = "Tingtube is on!";
my $username = 'tingtingss';
my $HTTP404 = '404 Not Found';
my $flag = 0;

$ua->timeout(10);
$ua->env_proxy;

my $pf = catfile(getcwd(), 'run/lolmatchalerter.pid');
my $daemon = Proc::Daemon->new(
		pid_file => $pf,
		work_dir => getcwd(),
		);
# are you running?  Returns 0 if not.
my $pid = $daemon->Status($pf);
my $daemonize = 1;

GetOptions(
		'daemon!' => \$daemonize,
		"start" => \&run,
		"status" => \&status,
		"stop" => \&stop,
		"restart" => \&restart,
	  );

sub getConfs {
	my $cfg = new Config::Simple();
	$cfg->read('/conf/sannie.conf');

	my $apikey = $cfg->param('api.key');
	my $sendEmailUser = $cfg->param('email.username');
	my $sendEmailPassword = $cfg->param('email.password');

}

sub stop {
	if ($pid) {
		print "Stopping pid $pid...\n";
		if ($daemon->Kill_Daemon($pf)) {
			print "Successfully stopped.\n";
			open(my $FH, '>>', catfile(getcwd(), "logs/lolmatchalerter.log"));
			print $FH "#I Tingtube script stopped  at " . time() . "\n";
			close $FH;
		} else {
			print "Could not find $pid.  Was it running?\n";
		}
	} else {
		print "Not running, nothing to stop.\n";
	}
}

sub status {
	if ($pid) {
		print "Running with pid $pid.\n";
	} else {
		print "Not running.\n";
	}
}

sub restart {
	stop();
	sleep 5;
	run();
}

sub run {
	if (!$pid) {
		print "Starting...\n";
		print Dumper $daemon->Init;
		my $summonerHash = getSummonerInfo( $username );

		while (1) {
			open(my $FH, '>>', catfile(getcwd(), "logs/lolmatchalerter.log"));
			print $FH "#I Tingtube script started  at " . time() . "\n";

			getMatchInfo( $summonerHash->{lc($username)}{id}, $FH );
			sleep 30;
			print $FH "#D Logging at " . time() . "\n";
			close $FH;
		}
    } else {
        print "Already Running with pid $pid\n";
    }
}

sub getSummonerInfo {
	my $summoner = shift;
	print "getting summoner info\n";
	my $response = $ua->get("https://na.api.pvp.net/api/lol/na/v1.4/summoner/by-name/$summoner?api_key=" . $API_Key);

	print "got summoner info\n";
	if ( $response->is_success ) {
		my $summonerInfo = parseResponse( $response );
		return $summonerInfo;
	} else {
		die $response->status_line;
	}
}

sub getMatchInfo {
	my $summonerID = shift;
	my $logs = shift;

#	print $logs "#D $flag Logging at " . time() . "\n";
	my $matchResponse = $ua->get("https://na.api.pvp.net/observer-mode/rest/consumer/getSpectatorGameInfo/$platform/$summonerID?api_key=" . $API_Key);
	if ( $matchResponse->is_success and $flag == 0 ) {
		my $ranked = parseResponse( $matchResponse );
#		print $logs "#D". Dumper $ranked->{bannedChampions} ." Logging at " . time() . "\n";
		
		my $blueBanned = getTeamsFromHash( getChampionInfo( $ranked->{bannedChampions} ), 100 );
		my $redBanned = getTeamsFromHash( getChampionInfo( $ranked->{bannedChampions} ), 200 );
#		print $logs "#D $blueBanned $redBanned Logging at " . time() . "\n";
		my $bluePicks = getTeamsFromHash( getChampionInfo( $ranked->{participants}), 100 );
		my $redPicks = getTeamsFromHash( getChampionInfo( $ranked->{participants}), 200 );
#		print $logs "#D $bluePicks $redPicks Logging at " . time() . "\n";
		if ( $ranked->{gameQueueConfigId} == RANKED ) {
#			print $logs "#D HEREHERE Logging at " . time() . "\n";
			
			$flag = 1;
			sendMail( $logs,      { 
						blueBans => $blueBanned,
						redBans => $redBanned, 
						bluePick => $bluePicks, 
						redPick => $redPicks, 
						});
		}
	} elsif ( $matchResponse->status_line eq $HTTP404 ) {
		$flag = 0;
	}
}

sub getChampionInfo {
	my $array = shift;

	my $picks; 
	foreach my $member ( @$array ) {
		my $championResponse = $ua->get("https://na.api.pvp.net/api/lol/static-data/na/v1.2/champion/$member->{championId}?api_key=" . $API_Key);
		my $champion = parseResponse( $championResponse );
		$picks->{$member->{teamId}}{$champion->{key}} = $champion->{name};
	}

	return $picks;
}

sub getTeamsFromHash {
	my $hash = shift;
	my $key = shift;

	my $string = join( ', ', keys( %{$hash->{$key}} ));
	return $string;
}
sub sendMail {
	my $logs = shift;
	my $params = shift;

	my $smtp = Net::SMTP::SSL->new( 'smtp.gmail.com', Port => 465, Debug => 1, Timeout => 20, Hello=>'tingtingsstube@gmail.com' );

	$smtp->auth ( $sender, $password ) or die "could not authenticate\n";
	my $receiver = ['teddybearx31@gmail.com'];

	$smtp->mail($sender);

	foreach my $email ( @{$receiver} ) {
		$smtp->to($email);
	}
	$smtp->data();
	$smtp->datasend("From: " . $sender. "\n" );
	$smtp->datasend("To: " . $receiver. "\n" );
	$smtp->datasend("Subject: " . $subject. "\n" );
	$smtp->datasend("\n" );
	$smtp->datasend($body . "\n" );
	$smtp->datasend("Bans: $params->{blueBans}, $params->{redBans}" . "\n" );
	$smtp->datasend("Blue picks: $params->{bluePick}" . "\n" );
	$smtp->datasend("Red picks: $params->{redPick}" . "\n" );
	$smtp->dataend();
	$smtp->quit;
	print $logs "Email Sent:  Logging at " . time() . "\n";
}

sub parseResponse{
	my $response = shift;

	my $info = $response->decoded_content;
	my $results = decode_json($info);

	return $results;
}

