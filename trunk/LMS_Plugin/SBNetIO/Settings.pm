package Plugins::SBNetIO::Settings;

# SqueezeCenter Copyright (c) 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Web::Settings); #driven by the web UI

use Slim::Utils::Strings qw(string); #we want to use text from the strings file
use Slim::Utils::Log; #we want to use the log methods
use Slim::Utils::Prefs; #we want access to the preferences methods

# ----------------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# References to other classes
# ----------------------------------------------------------------------------
my $classPlugin		= undef;

# ----------------------------------------------------------------------------
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sbnetio',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_SBNETIO_MODULE_NAME',
});

# ----------------------------------------------------------------------------
my $prefs = preferences('plugin.sbnetio'); #name of preferences

# ----------------------------------------------------------------------------
# Define own constructor
# - to save references to Plugin.pm
# ----------------------------------------------------------------------------
sub new {
	my $class = shift;

	$classPlugin = shift;

	$log->debug( "*** SBNetIO::Settings::new() " . $classPlugin . "\n");

	$class->SUPER::new();	

	return $class;
}

# ----------------------------------------------------------------------------
# Name in the settings dropdown
# ----------------------------------------------------------------------------
sub name { #this is what is shown in the players menu on the web gui
	return 'PLUGIN_SBNETIO_MODULE_NAME';
}

# ----------------------------------------------------------------------------
# Webpage served for settings
# ----------------------------------------------------------------------------
sub page { #tells which file to use as the web page
	return 'plugins/SBNetIO/settings/basic.html';
}

# ----------------------------------------------------------------------------
# Settings are per player
# ----------------------------------------------------------------------------
sub needsClient {
	return 1; #this means this is for a particular squeezebox, not the system
}

# ----------------------------------------------------------------------------
# Only show plugin for Squeezebox 3 or Receiver players
# ----------------------------------------------------------------------------
sub validFor {
	my $class = shift;
	my $client = shift;
	# Receiver and Squeezebox2 also means SB3
	return $client->isPlayer && ($client->isa('Slim::Player::Receiver') || 
		                         $client->isa('Slim::Player::Squeezebox2') ||
		                         $client->isa('Slim::Player::SqueezeSlave'));
}

# ----------------------------------------------------------------------------
# Handler for settings page
# ----------------------------------------------------------------------------
sub handler {
	my ($class, $client, $params) = @_; 
	#passes the class and client objects along with the parameters

	# $client is the client that is selected on the right side of the web interface!!!
	# We need the client identified by 'playerid'

	# Find player that fits the mac address supplied in $params->{'playerid'}
	my @playerItems = Slim::Player::Client::clients();
	foreach my $play (@playerItems) {
		if( $params->{'playerid'} eq $play->macaddress()) {
			$client = $play; #this particular player
			last;
		}
	}
	if( !defined( $client)) {
		#set the class object with the particular player
		return $class->SUPER::handler($client, $params); 
		$log->debug( "*** SBNetIO: found player: " . $client . "\n");
	}

	
	# Fill in name of player
	if( !$params->{'playername'}) {
		#get the player name but I don't use it
		$params->{'playername'} = $client->name(); 
		$log->debug( "*** SBNetIO: player name: " . $params->{'playername'} . "\n");
	}
	
	# set a few defaults for the first time
	if ($prefs->client($client)->get('delayOn') == '') {
		$prefs->client($client)->set('delayOn', '0');
	} 
	if ($prefs->client($client)->get('delayOff') == '') {
		$prefs->client($client)->set('delayOff', '30');
	}
	if ($prefs->client($client)->get('Zone1Active') == '') {
		$prefs->client($client)->set('Zone1Active', 1);
	}
	if ($prefs->client($client)->get('Zone2Active') == '') {
		$prefs->client($client)->set('Zone2Active', 0);
	}
	if ($prefs->client($client)->get('Zone3Active') == '') {
		$prefs->client($client)->set('Zone3Active', 0);
	}
	if ($prefs->client($client)->get('Zone1Name') eq "") {
		$prefs->client($client)->set('Zone1Name', 'Zone 1');
	}
	if ($prefs->client($client)->get('Zone2Name') eq "") {
		$prefs->client($client)->set('Zone2Name', 'Zone 2');
	}
	if ($prefs->client($client)->get('Zone3Name') eq "") {
		$prefs->client($client)->set('Zone3Name', 'Zone 3');
	}

	# When "Save" is pressed on the settings page, this function gets called.
	if ($params->{'saveSettings'}) {
		#store the enabled value in the client prefs
		if ($params->{'pref_Enabled'}){ #save the enabled state
			$prefs->client($client)->set('pref_Enabled', 1); 
		} else {
			$prefs->client($client)->set('pref_Enabled', 0);
		}
		
		# General settings --------------------------------------------------------------
		if ($params->{'srvAddress'}) { #save the Server IP Address
			my $srvAddress = $params->{'srvAddress'};
			# get rid of leading spaces if any since one is always added.
			$srvAddress =~ s/^\s+(.*)\s+/\1/;
			#save the AVP address in the client prefs
			$prefs->client($client)->set('srvAddress', "$srvAddress"); 
		}
		if ($params->{'delayOn'} =~ /^-?\d/) { #save the delay on time
			my $delayOn = $params->{'delayOn'};
			# get rid of leading spaces if any since one is always added.
			$delayOn =~ s/^\s+(.*)\s+/\1/;
			#save the delay on time in the client prefs
			$prefs->client($client)->set('delayOn', "$delayOn"); 
		}
		if ($params->{'delayOff'} =~ /^-?\d/) { #save the delay off time
			my $delayOff = $params->{'delayOff'};
			# get rid of leading spaces if any since one is always added.
			$delayOff =~ s/^\s+(.*)\s+/\1/;
			#save the delay off time in the client prefs
			$prefs->client($client)->set('delayOff', "$delayOff"); 
		}
		
		# Zone 1 --------------------------------------------------------------
		if ($params->{'Zone1Active'}){ 
			$prefs->client($client)->set('Zone1Active', 1); 
		} else {
			$prefs->client($client)->set('Zone1Active', 0);
		}
		if ($params->{'Zone1Name'}) { 
			my $ZoneName = $params->{'Zone1Name'};
			$prefs->client($client)->set('Zone1Name', "$ZoneName"); 
		}
		if ($params->{'Zone1Auto'}){ 
			$prefs->client($client)->set('Zone1Auto', 1); 
		} else {
			$prefs->client($client)->set('Zone1Auto', 0);
		}
		if ($params->{'msgOn1'}) { 
			my $msgOn = $params->{'msgOn1'};
			$prefs->client($client)->set('msgOn1', "$msgOn"); 
		}
		if ($params->{'msgOff1'}) { 
			my $msgOff = $params->{'msgOff1'};
			$prefs->client($client)->set('msgOff1', "$msgOff"); 
		}
		
		
		# Zone 2 --------------------------------------------------------------
		if ($params->{'Zone2Active'}){ 
			$prefs->client($client)->set('Zone2Active', 1); 
		} else {
			$prefs->client($client)->set('Zone2Active', 0);
		}
		if ($params->{'Zone2Name'}) { 
			my $ZoneName = $params->{'Zone2Name'};
			$prefs->client($client)->set('Zone2Name', "$ZoneName"); 
		}
		if ($params->{'Zone2Auto'}){ 
			$prefs->client($client)->set('Zone2Auto', 1); 
		} else {
			$prefs->client($client)->set('Zone2Auto', 0);
		}
		if ($params->{'msgOn2'}) { 
			my $msgOn = $params->{'msgOn2'};
			$prefs->client($client)->set('msgOn2', "$msgOn"); 
		}
		if ($params->{'msgOff2'}) { 
			my $msgOff = $params->{'msgOff2'};
			$prefs->client($client)->set('msgOff2', "$msgOff"); 
		}
		
		
		# Zone 3 --------------------------------------------------------------
		if ($params->{'Zone3Active'}){ 
			$prefs->client($client)->set('Zone3Active', 1); 
		} else {
			$prefs->client($client)->set('Zone3Active', 0);
		}
		if ($params->{'Zone3Name'}) { 
			my $ZoneName = $params->{'Zone3Name'};
			$prefs->client($client)->set('Zone3Name', "$ZoneName"); 
		}
		if ($params->{'Zone3Auto'}){ 
			$prefs->client($client)->set('Zone3Auto', 1); 
		} else {
			$prefs->client($client)->set('Zone3Auto', 0);
		}
		if ($params->{'msgOn3'}) { 
			my $msgOn = $params->{'msgOn3'};
			$prefs->client($client)->set('msgOn3', "$msgOn"); 
		}
		if ($params->{'msgOff3'}) { 
			my $msgOff = $params->{'msgOff3'};
			$prefs->client($client)->set('msgOff3', "$msgOff"); 
		}
	
	}

	# Puts the values on the webpage. 
	#next line takes the stored plugin pref value and puts it on the web page
	#set the enabled checkbox on the web page
	if($prefs->client($client)->get('pref_Enabled') == '1') {
		$params->{'prefs'}->{'pref_Enabled'} = 1; 
	}

	# this puts the text fields in the web page
	$params->{'prefs'}->{'srvAddress'} = $prefs->client($client)->get('srvAddress'); 
	$params->{'prefs'}->{'delayOn'} = $prefs->client($client)->get('delayOn'); 
	$params->{'prefs'}->{'delayOff'} = $prefs->client($client)->get('delayOff'); 
	
	#Zone 1
	if( $prefs->client($client)->get('Zone1Active') == '1'){
		$params->{'prefs'}->{'Zone1Active'} = 1;
	}
	else{
		$params->{'prefs'}->{'Zone1Active'} = 0;
	}
	if( $prefs->client($client)->get('Zone1Auto') == '1'){
		$params->{'prefs'}->{'Zone1Auto'} = 1;
	}
	else{
		$params->{'prefs'}->{'Zone1Auto'} = 0;
	}
	$params->{'prefs'}->{'Zone1Name'} = $prefs->client($client)->get('Zone1Name'); 
	$params->{'prefs'}->{'msgOn1'} = $prefs->client($client)->get('msgOn1'); 
	$params->{'prefs'}->{'msgOff1'} = $prefs->client($client)->get('msgOff1'); 
	
	#Zone 2
	if( $prefs->client($client)->get('Zone2Active') == '1'){
		$params->{'prefs'}->{'Zone2Active'} = 1;
	}	
	else{
		$params->{'prefs'}->{'Zone2Active'} = 0;
	}
	if( $prefs->client($client)->get('Zone2Auto') == '1'){
		$params->{'prefs'}->{'Zone2Auto'} = 1;
	}	
	else{
		$params->{'prefs'}->{'Zone2Auto'} = 0;
	}	
	$params->{'prefs'}->{'Zone2Name'} = $prefs->client($client)->get('Zone2Name'); 
	$params->{'prefs'}->{'msgOn2'} = $prefs->client($client)->get('msgOn2'); 
	$params->{'prefs'}->{'msgOff2'} = $prefs->client($client)->get('msgOff2'); 
	
	#Zone 3
	if( $prefs->client($client)->get('Zone3Active') == '1'){
		$params->{'prefs'}->{'Zone3Active'} = 1;
	}
	else{
		$params->{'prefs'}->{'Zone3Active'} = 0;
	}
	if( $prefs->client($client)->get('Zone3Auto') == '1'){
		$params->{'prefs'}->{'Zone3Auto'} = 1;
	}	
	else{
		$params->{'prefs'}->{'Zone3Auto'} = 0;
	}
	$params->{'prefs'}->{'Zone3Name'} = $prefs->client($client)->get('Zone3Name'); 
	$params->{'prefs'}->{'msgOn3'} = $prefs->client($client)->get('msgOn3'); 
	$params->{'prefs'}->{'msgOff3'} = $prefs->client($client)->get('msgOff3'); 
	
	
	return $class->SUPER::handler($client, $params);
}

1;

__END__

pref_Enabled