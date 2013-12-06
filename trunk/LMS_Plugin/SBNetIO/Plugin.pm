#	SBNetIO
#
#	Author:	Guenther Roll <guenther.roll(at)gmail(dot)com>
#
#   Credit to the authors of the DenonAvpControl-Plugin which I used as template and 
#   which largely pointed me the way through the difficulties of Perl and the Plugin API:
#
#           Chris Couper  <ccouper(at)fastkat(dot)com>
#	        Felix Mueller <felix(dot)mueller(at)gwendesign(dot)com>
#
#	Copyright (c) 2013 Guenther Roll
#	All rights reserved.
#
#	----------------------------------------------------------------------
#	Function:	Send network messages when players are turned on and off (tested fot SBT)
#	----------------------------------------------------------------------
#	Technical:	Sends a customizable network message when a player is turned on.
#			    Sends a customizable network message when a player is turned off.
#
#	----------------------------------------------------------------------
#	Installation:
#			- Copy the complete directory into the 'Plugins' directory
#			- Restart LMS
#			- Enable SBNetIO in the Web GUI interface
#			- Set: Server address, On and Off Delays, and the Messages to be send
#	----------------------------------------------------------------------
#	History:
#
#	2013/07/26 v1.0	- Initial version
#	----------------------------------------------------------------------
#
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
package Plugins::SBNetIO::Plugin;
use strict;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

use Slim::Player::Client;
use Slim::Player::Source;
use Slim::Player::Playlist;


use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use Plugins::SBNetIO::SBNetIOSendMsg;
use Plugins::SBNetIO::Settings;

#use Data::Dumper; #used to debug array contents

# ----------------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------------

# determines if the plugin initialization is complete
my $pluginReady=0; 
my $gMenuUpdate;	# Used to signal that no menu update should occur

my $gZone1ID = 1;
my $gZone2ID = 2;
my $gZone3ID = 4;


# Actual power state (needed for internal tracking)
my %PowerState;
my %InTransition;


# ----------------------------------------------------------------------------
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.SBNetIO',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_SBNETIO_MODULE_NAME',
});

# ----------------------------------------------------------------------------
my $prefs = preferences('plugin.SBNetIO');

# ----------------------------------------------------------------------------
sub initPlugin {
	my $classPlugin = shift;

	# Not Calling our parent class prevents adds it to the player UI for the audio options
	 $classPlugin->SUPER::initPlugin();

	# Initialize settings classes
	my $classSettings = Plugins::SBNetIO::Settings->new($classPlugin);

	# Install callback to get client setup
	Slim::Control::Request::subscribe( \&newPlayerCheck, [['client']],[['new']]);

	# init the SBNetIOSendMsg plugin
	Plugins::SBNetIO::SBNetIOSendMsg->new( $classPlugin);

	# Register dispatch methods
	
	#        |requires Client
	#        |  |is a Query
	#        |  |  |has Tags
	#        |  |  |  |Function to call
	#        C  Q  T  F
	Slim::Control::Request::addDispatch(['ShowTopMenuCB'],[1, 1, 0, \&ShowTopMenuCB]);
	Slim::Control::Request::addDispatch(['ShowZoneMenuCB', '_Zone'],[1, 1, 0, \&ShowZoneMenuCB]);
	Slim::Control::Request::addDispatch(['SetPowerStateCB', '_Powerstate'],[1, 1, 0, \&SetPowerStateCB]);
	Slim::Control::Request::addDispatch(['SetZonePowerCB', '_Zone', '_Powerstate'],[1, 1, 0, \&SetZonePowerCB]);
    Slim::Control::Request::addDispatch(['SetZoneSyncCB', '_Zone', '_Syncstate'],[1, 1, 0, \&SetZoneSyncCB]);
}

# ----------------------------------------------------------------------------
sub newPlayerCheck {
	my $request = shift;
	my $client = $request->client();
	
    if ( defined($client) ) {
	    $log->debug( "*** SBNetIO: ".$client->name()." is: " . $client);

		# Do nothing if client is not a Receiver or Squeezebox
		if( !(($client->isa( "Slim::Player::Receiver")) || ($client->isa( "Slim::Player::Squeezebox2")))) {
			$log->debug( "*** SBNetIO: Not a receiver or a squeezebox b \n");
			#now clear callback for those clients that are not part of the plugin
			clearCallback();
			return;
		}
		
		# Initialize Powerstate
		$PowerState{$client} = 0;
		my $Power = $client->power();
		if( $Power == 1 ){
			my $playmode = Slim::Player::Source::playmode($client);
			if( ($playmode eq "pause") || ($playmode eq "stop") ){
				$PowerState{$client} = 0;
			} else {
				$PowerState{$client} = 1;
			}
		}
		 
		$InTransition{$client} = 0;

		#init the client
		my $cprefs = $prefs->client($client);
		my $pluginEnabled = $cprefs->get('pref_Enabled');

		# Do nothing if plugin is disabled for this client
		if ( !defined( $pluginEnabled) || $pluginEnabled == 0) {
			$log->debug( "*** SBNetIO: Plugin Not Enabled for: ".$client->name()."\n");
			#now clear callback for those clients that are not part of the plugin
			clearCallback();
			return;
		} else {
			if ( $pluginEnabled == 1) {
				$log->debug( "*** SBNetIO: Plugin Enabled: \n");

				# Install callback to get client state changes
				Slim::Control::Request::subscribe( \&commandCallback, [['power', 'play', 'playlist', 'pause', 'client', 'mixer' ]], $client);			
				
				$log->debug("Calling the plugin menu register". "\n");
				# Create SP menu under audio settings	
				my $icon = 'plugins/SBNetIO/html/images/SBNetIO.png';
				my @menu = ({
					stringToken   => getDisplayName(),
					id     => 'pluginSBNetIO',
					icon => $icon,
					weight => 9,
					actions => {
						go => {
							player => 0,
							cmd	 => [ 'ShowTopMenuCB' ],
						}
					}
				});
				Slim::Control::Jive::registerPluginMenu(\@menu, 'extras' ,$client);
			}			
		}
	}
}

# ----------------------------------------------------------------------------
sub getDisplayName {
	return 'PLUGIN_SBNETIO';
}


# ----------------------------------------------------------------------------
sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&newPlayerCheck);
    clearCallback();
}


# ----------------------------------------------------------------------------
sub clearCallback {
	$log->debug( "*** SBNetIO:Clearing command callback" . "\n");
	Slim::Control::Request::unsubscribe(\&commandCallback);
}


# ----------------------------------------------------------------------------
# Callback to get client state changes
# ----------------------------------------------------------------------------
sub commandCallback {
	my $request = shift;

	my $client = $request->client();
	# Do nothing if client is not defined
	if(!defined( $client) || $pluginReady==0) {
		$pluginReady=1;
		return;
	}
	my $cprefs = $prefs->client($client);

	$log->debug( "*** SBNetIO: commandCallback() \n");
	$log->debug( "*** SBNetIO: commandCallback() p0: " . $request->{'_request'}[0] . "\n");
	$log->debug( "*** SBNetIO: commandCallback() p1: " . $request->{'_request'}[1] . "\n");

	if( $request->isCommand([['power']]) ){
		$log->debug("*** SBNetIO: power request $request \n");
		my $Power = $client->power();

		if( $Power == 0){
		    RequestPowerOff($client);
		}
	}
	elsif ( $request->isCommand([['play']])
	     || $request->isCommand([['pause']])
	     || $request->isCommand([['playlist'], ['stop']]) 
	     || $request->isCommand([['playlist'], ['newsong']]) ){
		 
		my $playmode    = Slim::Player::Source::playmode($client);
		$log->debug( "PLAYMODE " . $playmode . "\n");
		
		if( ($playmode eq "pause") || ($playmode eq "stop") ){
			if( ($PowerState{$client} == 1) || ($InTransition{$client} == 1) ){
				RequestPowerOff($client);
			}
		} else {
			if( ($PowerState{$client} == 0) || ($InTransition{$client} == -1) ){
				RequestPowerOn($client);
			}
		}
	} 
    # Get clients volume adjustment
	elsif ( $request->isCommand([['mixer'], ['volume']])) {
		# not used
	}
}


# ----------------------------------------------------------------------------
sub RequestPowerOn {
	my $client = shift;
	my $cprefs = $prefs->client($client);
	
	my $Delay = $cprefs->get('delayOn');	 
	
	$log->debug("*** SBNetIO: Request Power ON \n");
	$log->debug("*** SBNetIO: In transition = " . $InTransition{$client} . "\n");
	
	# Maybe we received a player off request recently - if so, stop TurnOff
	Slim::Utils::Timers::killTimers($client, \&TurnPowerOff); 

	if( $InTransition{$client} == -1 ){
		# If we are in transition to OFF state ($InTransition{$client} == -1)
		# there is nothing left to do, since the PowerOn was stopped above
		$log->debug("*** SBNetIO: Power ON requested while being in transition to OFF -> Cmds cancel, nothing to do. \n");
		
		my $msg = "SBNetIO: Zone turn off cancelled.";
		RunCommand( $client, ['display',$msg] );
	}
	else{
		# If we are already in a transition to ON state, kill the old Transition timer
		if( $InTransition{$client} == 1 ){
			Slim::Utils::Timers::killTimers( $client, \&ResetTransitionFlag); 
		}
		
		# Start ON transition
		$InTransition{$client} = 1;
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&ResetTransitionFlag); 
		
	    # Launch timer to power on after a delay		
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&TurnPowerOn); 
	}

}


# ----------------------------------------------------------------------------
sub RequestPowerOff {
	my $client = shift;
	my $Delay  = shift;
	my $cprefs = $prefs->client($client);
	
	my $Delay = $cprefs->get('delayOff');
	
	$log->debug("*** SBNetIO: Request Power OFF \n");
	$log->debug("*** SBNetIO: In transition = " . $InTransition{$client} . "\n");
	
	my $msg = "SBNetIO: Zones will be turned off in " . $Delay . " seconds.";
	RunCommand( $client, ['display',$msg] );
		
	# Maybe we received a player off request recently - if so, stop  TurnOn
	Slim::Utils::Timers::killTimers($client, \&TurnPowerOn); 

	if( ($InTransition{$client} == 1) ){
		# If we are in transition to ON state ($InTransition{$client} == 1)
		# there is nothing left to do, since the PowerOff was stopped above
		$log->debug("*** SBNetIO: Power Off requested while being in transition to ON -> Cmds cancel, nothing to do. \n");
	}
	else{
		# If we are already in a transition to OFF state, kill the old Transition timer
		if( $InTransition{$client} == -1){
			Slim::Utils::Timers::killTimers( $client, \&ResetTransitionFlag); 
		}
		
		# Start OFF transition
		$InTransition{$client} = -1;
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&ResetTransitionFlag); 
		
		# Launch timer to power off after a delay		
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&TurnPowerOff); 
	}

}


# ----------------------------------------------------------------------------
sub SetPowerState{
	my $client = shift;
	my $iPower = shift;
	
	$PowerState{$client} = $iPower;
	$InTransition{$client} = 0;
	
	$log->debug("*** SBNetIO: Turn Power: " . $iPower . "\n");
	
	my $cprefs = $prefs->client($client);
	
	my $Zones = 0;
	
	my $Zone1Active = $cprefs->get('Zone1Active');
	if( $Zone1Active == 1 ){
		my $Zone1Auto = $cprefs->get('Zone1Auto');
		if( $Zone1Auto == 1){
			$Zones = $Zones + $gZone1ID;
		}
	}
	
	my $Zone2Active = $cprefs->get('Zone2Active');
	if( $Zone2Active == 1 ){
		my $Zone2Auto = $cprefs->get('Zone2Auto');
		if( $Zone2Auto == 1){
			$Zones = $Zones + $gZone2ID;
		}
	}
	
	my $Zone3Active = $cprefs->get('Zone3Active');
	if( $Zone3Active == 1 ){
		my $Zone3Auto = $cprefs->get('Zone3Auto');
		if( $Zone3Auto == 1){
			$Zones = $Zones + $gZone3ID;
		}
	}
	
	if( $Zones > 0 ){
		SetZonePower($client, $Zones, $iPower);
	}
	
	Slim::Control::Jive::refreshPluginMenus($client); 
}


# ----------------------------------------------------------------------------
sub SetZonePower{
	my $client = shift;
	my $iZone = shift;
	my $iPower = shift;
	
	$log->debug("*** SBNetIO: SetZonePower: " . $iZone . " - " . $iPower . "\n");
	
	my $cprefs = $prefs->client($client);
	my $srvAddress = $cprefs->get('srvAddress');
	
	if( ($iZone & $gZone1ID) == $gZone1ID ){
		my $Cmd = '';
		if( $iPower == 1 ){
			$Cmd = $cprefs->get('msgOn1');
		}
		else{
			$Cmd = $cprefs->get('msgOff1');
		}
		$log->debug("*** SBNetIO: SetPower: Zone 1, Msg: " . $Cmd . "\n");
		Plugins::SBNetIO::SBNetIOSendMsg::SendCmd($srvAddress, $Cmd);
	}
	
	if( ($iZone & $gZone2ID) == $gZone2ID ){
		my $Cmd = '';
		if( $iPower == 1 ){
			$Cmd = $cprefs->get('msgOn2');
		}
		else{
			$Cmd = $cprefs->get('msgOff2');
		}
		$log->debug("*** SBNetIO: SetPower: Zone 2, Msg: " . $Cmd . "\n");
		Plugins::SBNetIO::SBNetIOSendMsg::SendCmd($srvAddress, $Cmd);
	}
	
	if( ($iZone & $gZone3ID) == $gZone3ID ){
		my $Cmd = '';
		if( $iPower == 1 ){
			$Cmd = $cprefs->get('msgOn3');
		}
		else{
			$Cmd = $cprefs->get('msgOff3');
		}
		$log->debug("*** SBNetIO: SetPower: Zone 3, Msg: " . $Cmd . "\n");
		Plugins::SBNetIO::SBNetIOSendMsg::SendCmd($srvAddress, $Cmd);
	}

}


# ----------------------------------------------------------------------------
sub SetZoneSync{
	my $client = shift;
	my $iZone = shift;
	my $iSync = shift;
	
	$log->debug("*** SBNetIO: SetZoneSync: " . $iZone . " - " . $iSync . "\n");
	
	my $cprefs = $prefs->client($client);
	
	if( ($iZone & $gZone1ID) == $gZone1ID ){
		$cprefs->set('Zone1Auto', $iSync);
	}
	
	if( ($iZone & $gZone2ID) == $gZone2ID ){
		$cprefs->set('Zone2Auto', $iSync);
	}
	
	if( ($iZone & $gZone3ID) == $gZone3ID ){
		$cprefs->set('Zone3Auto', $iSync);
	}
}


# ----------------------------------------------------------------------------
sub TurnPowerOn {
	my $client = shift;

	SetPowerState($client, 1)
}


# ----------------------------------------------------------------------------
sub TurnPowerOff {
	my $client = shift;
	
	SetPowerState($client, 0)
}


# ----------------------------------------------------------------------------
sub ResetTransitionFlag {
	my $client = shift;

	#flag end of transition (Good to know in case transition was cancelled before delay)
	$InTransition{$client} = 0;
}


# ----------------------------------------------------------------------------
# determine if this player is using the SBNetIO plugin and its enabled
sub usingSBNetIO() {
	my $client = shift;
	my $cprefs = $prefs->client($client);
	my $pluginEnabled = $cprefs->get('pref_Enabled');

 	if ($pluginEnabled == 1) {
		return 1;
	}
	
	return 0;
}



# ----------------------------------------------------------------------------
# Handlers for player based menu integration
# ----------------------------------------------------------------------------

# Generates the top menus as elements of the Extras menu
sub ShowTopMenuCB {
	my $request = shift;
	my $client = $request->client();
	my $cprefs = $prefs->client($client);
	my $pluginEnabled = $cprefs->get('pref_Enabled');
	
	my $iPower = $client->power();
	my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');

	# Do nothing if plugin is disabled for this client or the power is off
	if ( !defined( $pluginEnabled) || $pluginEnabled == 0 ) {
		$log->debug( "Plugin Not Enabled ... - no extra menu \n");
		return;
	}
	
	$gMenuUpdate = 0;
	$log->debug("Adding the menu elements to the Top menu". "\n");
		
	my @menu = ();
	
	# State ==============================================================================================
	
	my $Transit = $InTransition{$client};
	my $TextState = 'Unknown';
	my $IconState = 'plugins/SBNetIO/html/images/SBNetIO_Unkn.png';
	if( $Transit != 0 ){
		$IconState = 'plugins/SBNetIO/html/images/SBNetIO_Trans.png';
		if( $Transit == 1 ){
			$TextState = 'Power On scheduled';
		}
		else{
			$TextState = 'Power Off scheduled';
		}
	}
	else{
		my $PState = $PowerState{$client};
		if( $PState == 1){
			$TextState = 'Power On';
			$IconState = 'plugins/SBNetIO/html/images/SBNetIO_On.png';
		}
		if( $PState == 0){
			$TextState = 'Power Off';
			$IconState = 'plugins/SBNetIO/html/images/SBNetIO_Off.png';
		}	
	}
	
	push @menu,	{
		text => $TextState,
		icon => $IconState,
		id      => 'State',
	};
	
	my $Zones = 0;
	
	# ZONE 1 ==============================================================================================
	my $Zone1Active = $cprefs->get('Zone1Active');
	if( $Zone1Active == 1 ){
	    $Zones = $Zones +  $gZone1ID;
		my $Zone1Name = $cprefs->get('Zone1Name');
		
		my $IconZone1 = 'plugins/SBNetIO/html/images/SBNetIO_Zone.png';
		my $Zone1Auto = $cprefs->get('Zone1Auto');
		if( $Zone1Auto == 1){
			$IconZone1 = 'plugins/SBNetIO/html/images/SBNetIO_SyncedZone.png';
		}
		push @menu,	{
			text => $Zone1Name,
			id      => 'Zone1',
			icon => $IconZone1,
			actions  => {
				go  => {
					player => 0,
					cmd    => [ 'ShowZoneMenuCB', $gZone1ID],
					params	=> {
						menu => 'ShowZoneMenuCB',
					},
				},
			},
		};
	}
	
	
	# ZONE 2 ==============================================================================================
	my $Zone2Active = $cprefs->get('Zone2Active');
	if( $Zone2Active == 1 ){
		$Zones = $Zones + $gZone2ID;
		my $Zone2Name = $cprefs->get('Zone2Name');
		my $IconZone2 = 'plugins/SBNetIO/html/images/SBNetIO_Zone.png';
		my $Zone2Auto = $cprefs->get('Zone2Auto');
		if( $Zone2Auto == 1){
			$IconZone2 = 'plugins/SBNetIO/html/images/SBNetIO_SyncedZone.png';
		}
		push @menu,	{
			text => $Zone2Name,
			id      => 'Zone2',
			icon => $IconZone2,
			actions  => {
				go  => {
					player => 0,
					cmd    => [ 'ShowZoneMenuCB', $gZone2ID],
					params	=> {
						menu => 'ShowZoneMenuCB',
					},
				},
			},
		};
	}
	
	
	# ZONE 3 ==============================================================================================
	my $Zone3Active = $cprefs->get('Zone3Active');
	if( $Zone3Active == 1 ){
		$Zones = $Zones + $gZone3ID;
		my $Zone3Name = $cprefs->get('Zone3Name');
		my $IconZone3 = 'plugins/SBNetIO/html/images/SBNetIO_Zone.png';
		my $Zone3Auto = $cprefs->get('Zone3Auto');
		if( $Zone3Auto == 1){
		   $IconZone3 = 'plugins/SBNetIO/html/images/SBNetIO_SyncedZone.png';
		}
		push @menu,	{
			text => $Zone3Name,
			id      => 'Zone3',
			icon => $IconZone3,
			actions  => {
				go  => {
					player => 0,
					cmd    => [ 'ShowZoneMenuCB', $gZone3ID],
					params	=> {
						menu => 'ShowZoneMenuCB',
					},
				},
			},
		};
	}
	
	
	# =========================================================================================================
	
	if( $Zones > 0 ){
		my $IconOn  = 'plugins/SBNetIO/html/images/SBNetIO_TurnOn.png';
	    my $IconOff = 'plugins/SBNetIO/html/images/SBNetIO_TurnOff.png';
	
		push @menu,	{
			text => ' ',
			id      => 'Empty',
		};
		
		push @menu,	{
			text => $client->string('PLUGIN_SBNETIO_TURNONALLTITLE'),
			id      => 'turnonall',
			icon => $IconOn,
			nextWindow => "refresh",
			onClick => "refreshMe",
			actions  => {
				do  => {
					player => 0,
					cmd    => ['SetZonePowerCB', $Zones, 1],
				},
			},
		};
		
		push @menu,	{
			text => $client->string('PLUGIN_SBNETIO_TURNOFFALLTITLE'),
			id      => 'turnoffall',
			icon => $IconOff,
			nextWindow => "refresh",
			onClick => "refreshMe",
			actions  => {
				do  => {
					player => 0,
					cmd    => ['SetZonePowerCB', $Zones, 0],
				},
			},
		};
	}
	
	
	# =========================================================================================================
		
	my $numitems = scalar(@menu);
	
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachPreset (@menu[0..$#menu]) {
		$request->setResultLoopHash('item_loop', $cnt, $eachPreset);
		$cnt++;
	}
	
	$log->debug("done");
	$request->setStatusDone();
}


# ----------------------------------------------------------------------------
sub ShowZoneMenuCB { 
	my $request = shift;
	my $client = $request->client();

	my $Zone = $request->getParam('_Zone'); 
	
	my $IconOn  = 'plugins/SBNetIO/html/images/SBNetIO_TurnOn.png';
	my $IconOff = 'plugins/SBNetIO/html/images/SBNetIO_TurnOff.png';
	
	$log->debug("Adding the menu elements for Zone " . $Zone ."\n");

	my @menu = ();
	
	push @menu,	{
		text => $client->string('PLUGIN_SBNETIO_TURNONTITLE'),
		id      => 'turnon',
		icon => $IconOn,
		nextWindow => "refresh",
		onClick => "refreshMe",
		actions  => {
			do  => {
				player => 0,
				cmd    => ['SetZonePowerCB', $Zone, 1],
			},
		},
	};
	
	push @menu,	{
		text => $client->string('PLUGIN_SBNETIO_TURNOFFTITLE'),
		id      => 'turnoff',
		icon => $IconOff,
		nextWindow => "refresh",
		onClick => "refreshMe",
		actions  => {
			do  => {
				player => 0,
				cmd    => ['SetZonePowerCB', $Zone, 0],
			},
		},
	};
	
	
	my $cprefs = $prefs->client($client);
	
	my $Val = 0;
	
	if( $Zone == $gZone1ID ){
		$Val = $cprefs->get('Zone1Auto');
	}
	else{
		if( $Zone == $gZone2ID ){
			$Val = $cprefs->get('Zone2Auto');
		}
		else{
			if( $Zone == $gZone3ID ){
				$Val = $cprefs->get('Zone3Auto');
			}
		}
	}
	
	
	push @menu,	{
		text => "Sync Power",
		id      => 'sync',
		nextWindow => "refresh",
		onClick => "refreshOrigin",
		checkbox => $Val,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['SetZoneSyncCB', $Zone, 1],
			},
			off  => {
				player => 0,
				cmd    => ['SetZoneSyncCB', $Zone, 0],
			},
		},
	};
	
	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachItem (@menu[0..$#menu]) {
		$request->setResultLoopHash('item_loop', $cnt, $eachItem);
		$cnt++;
	}

	$request->setStatusDone();
}


# ----------------------------------------------------------------------------
sub SetPowerStateCB {
	my $request = shift;
	my $client = $request->client();
	my $cprefs = $prefs->client($client);

	my $RequestedPowerState = $request->getParam('_Powerstate');
	
	$log->debug("--> SetPowerstateCB: " . $RequestedPowerState . "\n");
	
	SetPowerState($client, $RequestedPowerState);
	
	$request->setStatusDone();
}


# ----------------------------------------------------------------------------
sub SetZonePowerCB {
	my $request = shift;
	my $client = $request->client();
	my $cprefs = $prefs->client($client);

	my $Zone = $request->getParam('_Zone');
	my $Power = $request->getParam('_Powerstate');
	
	$log->debug("--> SetZonePowerCB: " . $Zone . " - " . $Power ."\n");
	
	SetZonePower($client, $Zone, $Power);
	
	$request->setStatusDone();
}


# ----------------------------------------------------------------------------
sub SetZoneSyncCB {
	my $request = shift;
	my $client = $request->client();
	my $cprefs = $prefs->client($client);

	my $Zone = $request->getParam('_Zone');
	my $Sync = $request->getParam('_Syncstate');
	
	$log->debug("--> SetZoneSyncCB: " . $Zone . " - " . $Sync ."\n");
	
	SetZoneSync($client, $Zone, $Sync);
	
	$request->setStatusDone();
}


# ----------------------------------------------------------------------------
sub RunCommand{
    # Send a command to SC
    # eg. scCommand( $client, ['display', 'Xxx', 'Yyy', '30'] );
    my $client  = shift;
    my $args    = shift;
    my $id      = $client ? $client->id() : undef;
    my $argstr  = $$args[0];
    my $request;
    
    for( my $i=1; $i<=$#$args; $i++ ) {
        $argstr .= ' ' . $$args[$i];
    }
    $log->debug( sprintf( '--> %s %s', $id, $argstr ));
    $request = Slim::Control::Request->new( $id, $args, 1 );
    $request->execute();
    if( $request->isStatusError() ) {
        $log->debug( sprintf( 'Command ERROR --> %s %s', $id, $argstr ));
    }
}    


1;
