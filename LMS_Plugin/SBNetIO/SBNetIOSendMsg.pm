#	SBNetIO
#
#	Author:	Günther Roll <guenther.roll(at)gmail(dot)com>
#
#	Copyright (c) 2013 Guenther Roll
#	All rights reserved.
#
#	----------------------------------------------------------------------
#	Function:	Send TCP Commands to support SBNetIO plugin
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
use Slim::Networking::SimpleAsyncHTTP;
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
sub SendCmd{
	my $Addr = shift;
	my $Cmd = shift;
	my $timeout = 1;
	
	$log->debug("SendCmd - Addr: " . $Addr . ", Cmd: " . $Cmd . "\n");
	
	my $http = "http://";
	
	if( index($Addr, $http) == 0 ) {
		HTTPSend($Addr, $Cmd);
	}
	else{
		SocketSend($Addr, $Cmd);
	}	
}


# ----------------------------------------------------------------------------
sub SocketSend{
	my $Addr = shift;
	my $Cmd = shift;
	my $timeout = 1;
	
	$log->debug("SocketSend - Addr: " . $Addr . ", Cmd: " . $Cmd . "\n");
	
	my @parts = split(':', $Addr);
	my $Anzahl = @parts;
	if( $Anzahl == 2 ){
		my $IPAddr = @parts[0];
		my $Port   = @parts[1];
		
		my $request = $Cmd . "\n";
		
		my $sock = new IO::Socket::INET(
		   PeerAddr => $IPAddr, 
		   PeerPort => $Port, 
		   Proto => 'tcp', ); 
		die "Could not create socket: $!\n" unless $sock;
		
		$sock->autoflush(1);
		$sock->send($request);
		
		shutdown($sock, 2) if $sock;
		close($sock) if $sock;
	}
	else{
		$log->debug("Invalid Adress\n");	
	}
}


# ----------------------------------------------------------------------------
sub HTTPSend{
	my $Addr = shift;
	my $Cmd = shift;
	my $timeout = 1;
	
	$log->debug("HTTPSend - Addr: " . $Addr . ", Cmd: " . $Cmd . "\n");
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
			\&HttpSuccessCB,
			\&HttpErrorCB, 
			{
				#mydata'  => 'foo',
				#cache    => 0,		# optional, cache result of HTTP request
				#expires => '1h',	# optional, specify the length of time to cache
			}
	);
	
	my $url = $Addr . "/" . $Cmd;
	
	$http->get($url);
}


# ----------------------------------------------------------------------------
sub HttpErrorCB {
    my $http = shift;

    $log->debug("Oh no! An error!\n");
}


# ----------------------------------------------------------------------------
sub HttpSuccessCB{
    my $http = shift;

    my $content = $http->content();
	
	$log->debug("HTTP Response: " . $content . "\n");
}


1;