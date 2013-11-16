#	SBNetIO
#
#	Author:	Günther Roll <guenther.roll(at)gmail(dot)com>
#
#	Copyright (c) 2013 Guenther Roll
#	All rights reserved.
#
#	----------------------------------------------------------------------
#	Function:	Send HTTP Commands to support SBNetIO plugin
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
#	02111-1307 USA
#
package Plugins::SBNetIO::SBNetIOSendMsg;

use strict;
use base qw(Slim::Networking::Async);

use URI;
use IO::Socket;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Socket qw(:crlf);

# ----------------------------------------------------------------------------
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.SBNetIO',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_SBNETIO_MODULE_NAME',
});

# ----------------------------------------------------------------------------
# Global Variables
# ----------------------------------------------------------------------------
	my $prefs = preferences('plugin.SBNetIO'); #name of preferences
	my $self;
	my $gGetPSModes=0;	# looping through the PS modes

# ----------------------------------------------------------------------------
# References to other classes
# ----------------------------------------------------------------------------
my $classPlugin		= undef;


# ----------------------------------------------------------------------------
sub new {
	my $ref = shift;
	$classPlugin = shift;

	$log->debug( "*** SBNetIO::SBNetIOSendMsg::new() " . $classPlugin . "\n");
	$self = $ref->SUPER::new;
}


# ----------------------------------------------------------------------------
sub SendMsg{
	my $client = shift;
	my $url = shift;
	my $Cmd = shift;
	my $timeout = 1;
	
	my $request = $Cmd . $CR;

	$log->debug("Send msg: " . $Cmd . " to " . $url . "\n");	
	
	SendSock($request, $client, $url, $timeout);
}


# ----------------------------------------------------------------------------
sub SendSock{
	my $client = shift;
	my $url = shift;
	my $Cmd = shift;
	my $timeout = 1;
	
	my $request = $Cmd . $CR;

	$log->debug("Send Sock msg: " . $Cmd . " to " . $url . "\n");	
	
    my $sock = new IO::Socket::INET(
	   PeerAddr => '192.168.1.16', 
	   PeerPort => '54321', 
	   Proto => 'tcp', ); 
	die "Could not create socket: $!\n" unless $sock;
	
	$sock->send($request);
	shutdown($sock, 1);
	$sock->close();
}


# ----------------------------------------------------------------------------
sub writemsg {
	my $request = shift;
	my $client = shift;
	my $url = shift;
	my $timeout = shift;	

#	$log->debug("Command url: " . $url);

	my $u = URI->new($url);
	my @pass = [ $request, $client ];

	if (!$timeout) {
		$timeout = .125;
	}

	$self->write_async( {
		host        => $u->host,
		port        => $u->port,
		content_ref => \$request,
		Timeout     => $timeout,
		skipDNS     => 1,
		onError     => \&_error,
		onRead      => \&_read,
		passthrough => [ $url, @pass ],
		} );
	$log->debug("Sent command request: " . $request);
}


# ----------------------------------------------------------------------------
sub _error {
	my $self  = shift;
	my $errormsg = shift;
	my $url   = shift;
	my $track = shift;
	my $args  = shift;
	$log->debug("error routine called");

	$self->disconnect;

	my $error = "error connecting to url: error=$errormsg url=$url";
	$log->warn($error);
}


# ----------------------------------------------------------------------------
sub getCRLine($$) {
	my $socket = shift;
	my $maxWait = shift;
	my $buffer = '';
	my $start = Time::HiRes::time();
	my $c;
	my $r;
	B: while ( (Time::HiRes::time() - $start) < $maxWait ) {
		$r = $socket->read($c,1);
		if ( $r < 1 ) { next B; }
		$buffer .= $c;
		if ( $c eq "\r" ) { return $buffer; }
	}
	return $buffer;
}


# ----------------------------------------------------------------------------
sub _read {
	my $self  = shift;
	my $url   = shift;
	my $track = shift;
	my $args  = shift;

	my $buf;
	my @track = @$track;
	my $i;
	my $sSM;
	my $request = @track[0];
	my $client = @track[1];
	my $len;
	my $subEvent;
	my $event;
	my $callbackOK; 	# the returned message when the command was successful
	my $callbackError; 	# the returned message when the command was not successful

	$log->debug("read routine called");
    $buf = &getCRLine($self->socket,.125);
    my $read = length($buf);
#	my $read = sysread($self->socket, $buf, 1024); # do our own sysread as $self->socket->sysread assumes http
#	my $read = sysread($self->socket, $buf, 135); # do our own sysread as $self->socket->sysread assumes http

	if ($read == 0) {
		$callbackOK = "";
		$self->_error("End of file", $url, $track, $args);
		return;
	} else {
		$callbackOK = $buf;
		$log->debug("Read ".$read."\n");
	}

	$log->debug("Buffer read ".$buf."\n");
	$log->debug("Client name: " . $client->name . "\n");	
	
	$self->disconnect;
	

# #	if ($gGetPSModes == -1 || $gGetPSModes == 5) {
# #		$log->debug("Disconnecting Comms Session. gGetPSModes:" . $gGetPSModes . "\n");		
# #		Slim::Utils::Timers::killTimers( $client, \&SendTimerLoopRequest);
# #		$self->disconnect;
# #		$gGetPSModes =0;
# #	}

	# # see what is coming back from the AVP
	# my $command = substr($request,0,3);
	# $log->debug("Command is:" .$request);

	# $log->debug("Subcommand is:" .$command. "\n");
	# if ($request =~ m/PWON\r/ || $request =~ m/PW\?\r/) {	# power on or status
		# if ($buf eq 'PWON'. $CR) {
			# $self->disconnect;
			# $log->debug("Calling HandlePowerOn\n");	
			# $classPlugin->handlePowerOn($client);
		# } elsif ($buf eq 'PWOFF'. $CR) {
			# $log->debug("Calling HandlePowerOn\n");	
			# $classPlugin->handlePowerOn($client);
		# }
	# }
	# } elsif ($request =~ m/Z\d\?\r/) {	# zone power on
		# $log->debug("Calling HandlePowerOn for Zone\n");	
		# $classPlugin->handlePowerOn($client);
	# } elsif (substr($request,0,7) eq 'MSQUICK') { # quick setting
		# if ($buf eq 'PWON'. $CR) {
			# $self->disconnect;
			# SendNetAvpVolSetting($client, $url);
		# }
	# } elsif ($request =~ m/PWSTANDBY\r/) { #standby
		# $log->debug("Disconnect socket after Standby"."\n");
		# if ($buf eq 'PWSTANDBY'. $CR) {
			# $self->disconnect;
		# }
	# } elsif ($request =~ m/MV\?/) {
			# $log->debug("Volume setting inquiry"."\n");
			# $event = substr($buf,0,2);
			# if ($event eq 'MV') { #check to see if the element is a volume
				# $subEvent = substr($buf,2,3);
			  # if ($subEvent eq 'MAX') { # its not the one that tells us the volume change
					# $self->disconnect;		
				# } else {
					# # call the plugin routine to deal with the volume
					# $classPlugin->updateSqueezeVol($client, $subEvent);
				# }
			# }
	# } elsif ($request =~ m/MV/) {
			# $log->debug("Process Volume Setting"."\n");
			# $self->disconnect;
	# } elsif ($request =~ m/MS\?/ || $request =~ m/PS\?/ || $request =~ m/PSREFLEV\s\?/) {
		# my @events = split(/\r/,$buf); #break string into array
		# foreach $event (@events) { # loop through the event array parts
			# $log->debug("The value of the array element is: " . $event . "\n");			
			# $command = substr($event,0,2);
			# if ($command eq 'MS') { #check to see if the element is a surround mode
				# $i=0;
				# $subEvent = substr($events[0],0,5);
				# foreach (@surroundModes) {
					# $sSM = substr($surroundModes[$i],0,5);
					# if ($subEvent eq $sSM || ((substr($events[0],3,2) eq "CH") && ($sSM eq "MS7CH"))) {
						# # call the surround mode plugin routine to set the value
						# $log->debug("Surround Mode is: " . $surroundModes[$i] . "\n");
						# $classPlugin->updateSurroundMode($client, $i);
					# }
					# $i++;
				# } # foreach (@surroundModes)
			# } elsif ($command eq 'PS') { #check to see if the element is a PS mode
				# $subEvent = substr($events[0],0,6);
				# if ( $subEvent eq 'PSROOM') { #room modes
					# $i=0;
					# foreach (@roomModes) {
						# if ($roomModes[$i] eq $events[0]) {
							# # call the room mode plugin routine to set the value
							# $log->debug("Room Mode is: " . $roomModes[$i] . "\n");
							# $classPlugin->updateRoomEq($client, $i);
						# } # if
						# $i++;
					# } # foreach roomModes
				# } elsif ($subEvent eq 'PSDYNS') { # night mode
					# $i=0;
					# foreach (@nightModes) {
						# if ($nightModes[$i] eq $events[0]) {
							# # call the night mode plugin routine to set the value
							# $log->debug("Night Mode is: " . $nightModes[$i] . "\n");
							# $classPlugin->updateNM($client, $i);
						# } # if
						# $i++;
					# } # foreach nightModes
				# } elsif ($subEvent eq 'PSDYN ') { # dynamic volume
					# $i=0;
					# foreach (@dynamicVolModes) {
						# if ($dynamicVolModes[$i] eq $events[0]) {
							# # call the dynamic vol mode plugin routine to set the value
							# $log->debug("Dynamic Volume Mode is: " . $dynamicVolModes[$i] . "\n");
							# $classPlugin->updateDynEq($client, $i);
						# } # if
						# $i++;
					# } # foreach dynamicVolModes
				# } elsif ($subEvent eq 'PSRSTR') { # restorer
					# $i=0;
					# foreach (@restorerModes) {
						# if ($restorerModes[$i] eq $events[0])  {
							# # call the restorer mode plugin routine to set the value
							# $log->debug("Restorer Mode is: " . $restorerModes[$i] . "\n");
							# $classPlugin->updateRestorer($client, $i);
						# } # if
						# $i++;
					# } # foreach restorerModes
				# } elsif ($subEvent eq 'PSREFL') { # reference level
					# $i=0;
					# foreach (@refLevelModes) {
						# if ($refLevelModes[$i] eq $events[0])  {
							# # call the refence level plugin routine to set the value
							# $log->debug("Reference level is: " . $refLevelModes[$i] . "\n");
							# $classPlugin->updateRefLevel($client, $i);
						# } # if
						# $i++;
					# } # foreach refLevelModes
				# }
			# }
		# } # foreach (@events)
		# # now see if we should loop the AVP settings
# #		if ($gGetPSModes !=0) {
# #			$gGetPSModes++;
# #			LoopGetAvpSettings($client, $url);
# #		}
	# } # if ($request =~ /PWON\r/) {	# power on ...

} # _read

1;