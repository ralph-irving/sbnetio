#	SBNetIO
#
#	Author:	Guenther Roll <guenther.roll(at)gmail(dot)com>
#
#   Credit to the authors of the DenonAvpControl-Plugin which I used as template:
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

#	# getexternalvolumeinfo
#	$getexternalvolumeinfoCoderef = Slim::Control::Request::addDispatch(['getexternalvolumeinfo'],[0, 0, 0, \&getexternalvolumeinfoCLI]);
#	$log->debug( "*** SBNetIO: getexternalvolumeinfoCoderef: ".$getexternalvolumeinfoCoderef."\n");
#	# Register dispatch methods for Audio menu options
#	$log->debug("Getting the menu requests". "\n");
#	
#	#        |requires Client
#	#        |  |is a Query
#	#        |  |  |has Tags
#	#        |  |  |  |Function to call
#	#        C  Q  T  F
#
	Slim::Control::Request::addDispatch(['SBNetIO_TopMenu'],[1, 1, 0, \&SBNetIO_TopMenu]);
#	Slim::Control::Request::addDispatch(['avpSM'],[1, 1, 0, \&avpSM]);
#	Slim::Control::Request::addDispatch(['avpRmEq'],[1, 1, 0, \&avpRmEq]);
#	Slim::Control::Request::addDispatch(['avpDynEq'],[1, 1, 0, \&avpDynEq]);
#	Slim::Control::Request::addDispatch(['avpNM'],[1, 1, 0, \&avpNM]);
#	Slim::Control::Request::addDispatch(['avpRes'],[1, 1, 0, \&avpRes]);
#	Slim::Control::Request::addDispatch(['avpRefLvl'],[1, 1, 0, \&avpRefLvl]);
	Slim::Control::Request::addDispatch(['avpSetSM', '_powerstate'],[1, 1, 0, \&avpSetSM]);
#	Slim::Control::Request::addDispatch(['avpSetRmEq', '_roomEq', '_oldRoomEq'],[1, 1, 0, \&avpSetRmEq]);
#	Slim::Control::Request::addDispatch(['avpSetDynEq', '_dynamicEq', '_oldDynamicEq'],[1, 1, 0, \&avpSetDynEq]);
#	Slim::Control::Request::addDispatch(['avpSetNM', '_nightMode', '_oldNightMode'],[1, 1, 0, \&avpSetNM]);
#	Slim::Control::Request::addDispatch(['avpSetRes', '_restorer', '_oldRestorer'],[1, 1, 0, \&avpSetRes]);
#	Slim::Control::Request::addDispatch(['avpSetRefLvl', '_refLevel', '_oldRefLevel'],[1, 1, 0, \&avpSetRefLvl]);
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
		
		my $iPower = $client->power();
		
		# Powerstate unknown
		$PowerState{$client} = -1;
		 
		$InTransition{$client} = 0;

		#init the client
		my $cprefs = $prefs->client($client);
		my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');
		my $pluginEnabled = $cprefs->get('pref_Enabled');

		# Do nothing if plugin is disabled for this client
		if ( !defined( $pluginEnabled) || $pluginEnabled == 0) {
			$log->debug( "*** SBNetIO: Plugin Not Enabled for: ".$client->name()."\n");
			#now clear callback for those clients that are not part of the plugin
			clearCallback();
			return;
		} else {
			$log->debug( "*** SBNetIO: Plugin Enabled: \n");
			$log->debug( "*** SBNetIO: IP Address: " . $srvAddress . "\n");

			# Install callback to get client state changes
			Slim::Control::Request::subscribe( \&commandCallback, [['power', 'play', 'playlist', 'pause', 'client', 'mixer' ]], $client);			
			
			$log->debug("Calling the plugin menu register". "\n");
			# Create SP menu under audio settings	
			my $icon = 'plugins/SBNetIO/html/images/SBNetIO.png';
			my @menu = ({
				stringToken   => getDisplayName(),
				id     => 'pluginSBNetIO',
				menuIcon => $icon,
				weight => 9,
				actions => {
					go => {
						player => 0,
						cmd	 => [ 'SBNetIO_TopMenu' ],
					}
				}
			});
			Slim::Control::Jive::registerPluginMenu(\@menu, 'extras' ,$client);	
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
	
	my $PowerOnDelay = $cprefs->get('delayOn');	    # Delay to turn on amplifier after player has been turned on (in seconds)
	my $PowerOffDelay = $cprefs->get('delayOff');	# Delay to turn off amplifier after player has been turned off (in seconds)
	my $PausePowerOffDelay = 2 * $PowerOffDelay;

	
	# Get power on and off commands
	# Sometimes we do get only a power command, sometimes only a play/pause command and sometimes both
	if ( $request->isCommand([['power']])
	  || $request->isCommand([['play']])
	  || $request->isCommand([['pause']])
	  || $request->isCommand([['playlist'], ['stop']]) 
	  || $request->isCommand([['playlist'], ['newsong']]) ){
	  
		if( $request->isCommand([['power']]) ){
			$log->debug("*** SBNetIO: power request $request \n");
			my $iPower = $client->power();
		
			# Check with last known power state -> if different switch modes
			if ( $PowerState{$client} ne $iPower) {
			
				$log->debug("*** SBNetIO: commandCallback() Power: $iPower \n");

				if( $iPower == 1) {
					RequestPowerOn($client, $PowerOnDelay);
				} else {
				    RequestPowerOff($client, $PowerOffDelay);
				}
			}
		}
		else{
		    if( $request->isCommand([['playlist'], ['stop']]) ){
				RequestPowerOff($client, $PausePowerOffDelay);
			}
			else{
				if( $request->isCommand([['pause']]) ){
					#if 1) power is unknown or ON or 2) we are in transition to ON, request power OFF
					if( ($PowerState{$client} == 1) || ($InTransition{$client} == 1) ){
						RequestPowerOff($client, $PausePowerOffDelay);
					}
					else{
						if( ($PowerState{$client} == 0) || ($InTransition{$client} == -1) ){
							RequestPowerOn($client, $PowerOnDelay);
						}
					}
				}
				else{
					#if 1) power is unknown or OFF or 2) we are in transition to OFF, request power ON
					if( ($PowerState{$client} == -1) || ($PowerState{$client} == 0) || ($InTransition{$client} == -1) ){
						RequestPowerOn($client, $PowerOnDelay);
					}
				}
			}
		}
	} 
    # Get clients volume adjustment
	elsif ( $request->isCommand([['mixer'], ['volume']])) {
		my $volAdjust = $request->getParam('_newvalue');

		Slim::Utils::Timers::killTimers( $client, \&handleVolChanges);
		Slim::Utils::Timers::setTimer( $client, (Time::HiRes::time() + .125), \&handleVolChanges, $volAdjust);		
	}
}


# ----------------------------------------------------------------------------
sub handleVolChanges {
	my $client = shift;
	my $Vol = shift;
	my $cprefs = $prefs->client($client);
	my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');

	$log->debug("*** SBNetIO: VolChange: $Vol \n");
	Plugins::SBNetIO::SBNetIOSendMsg::SendNetVolume($client, $srvAddress, $Vol);
}


# ----------------------------------------------------------------------------
sub RequestPowerOn {
	my $client = shift;
	my $Delay  = shift;
	my $cprefs = $prefs->client($client);
	
	$log->debug("*** SBNetIO: Request Power ON \n");
	$log->debug("*** SBNetIO: In transition = " . $InTransition{$client} . "\n");
	
	# If player is turned on within delay, kill delayed power off timer
	Slim::Utils::Timers::killTimers($client, \&TurnPowerOff); 
	
	# If we are not in a transition to OFF state ...
	if( $InTransition{$client} > -1 ){
		
		# If we are already in a transition to ON state, kill timer
		if( $InTransition{$client} == 1){
			Slim::Utils::Timers::killTimers( $client, \&ResetTransitionFlag); 
		}
		
		# flag ON transition
		$InTransition{$client} = 1;
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&ResetTransitionFlag); 
		
	    # Launch timer to power on after a delay		
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&TurnPowerOn); 
	}
	else{
	    $log->debug("*** SBNetIO: Power ON requested while being in transition to OFF -> Cmds cancel, nothing to do. \n");
	}
}


# ----------------------------------------------------------------------------
sub RequestPowerOff {
	my $client = shift;
	my $Delay  = shift;
	my $cprefs = $prefs->client($client);
	
	$log->debug("*** SBNetIO: Request Power OFF \n");
	$log->debug("*** SBNetIO: In transition = " . $InTransition{$client} . "\n");
	
	my $msg = 'Power will be turned off soon';
	RunCommand( $client, ['display',$msg] );
		
	# If player is turned off within delay, kill delayed power on timer
	Slim::Utils::Timers::killTimers($client, \&TurnPowerOn); 

	# If we are not in a transition to ON state
	if( ($InTransition{$client} < 1) ){
		
		# If we are already in a transition to OFF state, kill timer
		if( $InTransition{$client} == -1){
			Slim::Utils::Timers::killTimers( $client, \&ResetTransitionFlag); 
		}
		
		# flag OFF transition
		$InTransition{$client} = -1;
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&ResetTransitionFlag); 
		
		# Launch timer to power off after a delay		
		Slim::Utils::Timers::setTimer($client, (Time::HiRes::time() + $Delay), \&TurnPowerOff); 
	}
	else{
	    $log->debug("*** SBNetIO: Power Off requested while being in transition to ON -> Cmds cancel, nothing to do. \n");
	}
}


# ----------------------------------------------------------------------------
sub TurnPowerOn {
	my $client = shift;
	my $cprefs = $prefs->client($client);
	my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');
	
	#flag power state as ON
	$PowerState{$client}   = 1;
	
	#flag end of transition
	$InTransition{$client} = 0;
	
	$log->debug("*** SBNetIO: Turn Power ON \n");
	Plugins::SBNetIO::SBNetIOSendMsg::SendNetPowerOn($client, $srvAddress);
	
	Slim::Control::Jive::refreshPluginMenus($client); 
}


# ----------------------------------------------------------------------------
sub TurnPowerOff {
	my $client = shift;
	my $cprefs = $prefs->client($client);
	my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');
	
	#flag power state as OFF
	$PowerState{$client}   = 0;
	
	#flag end of transition
	$InTransition{$client} = 0;

	$log->debug("*** SBNetIO: Turn Power OFF \n");
	Plugins::SBNetIO::SBNetIOSendMsg::SendNetPowerOff($client, $srvAddress);
	
	Slim::Control::Jive::refreshPluginMenus($client); 
}


# ----------------------------------------------------------------------------
sub ResetTransitionFlag {
	my $client = shift;

	#flag end of transition (In case transition was cancelled before delay)
	$InTransition{$client} = 0;
}


# ----------------------------------------------------------------------------
# determine if this player is using the SBNetIO plugin and its enabled
sub usingSBNetIO() {
	my $client = shift;
	my $cprefs = $prefs->client($client);
	my $pluginEnabled = $cprefs->get('pref_Enabled');

	# cannot use DS if no digital out (as with Baby)
	if ( (!$client->hasDigitalOut()) || ($client->model() eq 'baby')) {
		return 0;
	}
 	if ($pluginEnabled == 1) {
		return 1;
	}
	return 0;
}



# ----------------------------------------------------------------------------
# Handlers for player based menu integration
# ----------------------------------------------------------------------------

# Generates the top menus as elements of the Extras menu
sub SBNetIO_TopMenu {
	my $request = shift;
	my $client = $request->client();
	my $cprefs = $prefs->client($client);
	my $pluginEnabled = $cprefs->get('pref_Enabled');
	
	my $iPower = $client->power();
	my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');
	my $refIcon = 'plugins/SBNetIO/html/images/SBNetIO_3.png';

	# Do nothing if plugin is disabled for this client or the power is off
	if ( !defined( $pluginEnabled) || $pluginEnabled == 0 ) {
		$log->debug( "Plugin Not Enabled ... - no extra menu \n");
		return;
	}
	
	$gMenuUpdate = 0;
	$log->debug("Adding the menu elements to the menu". "\n");
	
	my $PState = $PowerState{$client};
	
	my $IconOn = 'plugins/SBNetIO/html/images/SBNetIO_NotOn.png';
	my $IconOff = 'plugins/SBNetIO/html/images/SBNetIO_NotOff.png';
	my $IconZone = 'plugins/SBNetIO/html/images/SBNetIO_Zones.png';
	
	if( $PState == 1){
		$IconOn = 'plugins/SBNetIO/html/images/SBNetIO_On.png';
	}
	
	if( $PState == 0){
		$IconOff = 'plugins/SBNetIO/html/images/SBNetIO_Off.png';
	}
	
	my @menu = ();
	# push @menu,	{
		# text => $client->string('PLUGIN_SBNETIO_TOGGLESTATE'),
		# id      => 'togglestate',
		# checkbox => $check,
		# actions  => {
			# on  => {
				# player => 0,
                # cmd    => ['avpSetSM', 1],
            # },
            # off => {
                # player => 0,
                # cmd    => ['avpSetSM', 0],
			# },
		# },
	# };
	
	push @menu,	{
		text => 'Zone 1',
		icon => $IconZone,
		id      => 'zone1',
	};
	
	push @menu,	{
		text => $client->string('PLUGIN_SBNETIO_TURNONTITLE'),
		id      => 'turnon',
		icon => $IconOn,
		nextWindow => "refresh",
		onClick => "refreshMe",
		actions  => {
			do  => {
				player => 0,
				cmd    => ['avpSetSM', 1],
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
				cmd    => ['avpSetSM', 0],
			},
		},
	};
		
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


# # Generates the Surround Mode menu, which is a list of all surround modes
# sub avpSM {
	# my $request = shift;
	# my $client = $request->client();
	# my $cprefs = $prefs->client($client);
	# my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');
	
	# my @menu = ();
	# my $i = 0;
	# my $check;
	# $gMenuUpdate = 1; # update menus from avp

	# $log->debug("The value of surroundMode is:" . "\n");
	
	# $check = 1;

	# push @menu, {
		# text => $client->string('PLUGIN_DENONAVPCONTROL_SURMD'.($i+1)),
		# radio => $check,
        # actions  => {
           # do  => {
               	# player => 0,
               	# cmd    => [ 'avpSetSM', 1 , $surroundMode],
           	# },
         # },

	# my $numitems = scalar(@menu);

	# $request->addResult("count", $numitems);
	# $request->addResult("offset", 0);
	# my $cnt = 0;
	# for my $eachItem (@menu[0..$#menu]) {
		# $request->setResultLoopHash('item_loop', $cnt, $eachItem);
		# $cnt++;
	# }
	# $request->setStatusDone();

# }


# ----------------------------------------------------------------------------
sub avpSetSM { # used to set the AVP surround mode
	my $request = shift;
	my $client = $request->client();
	my $cprefs = $prefs->client($client);

	my $RequestedPowerState = $request->getParam('_powerstate');
	
	$log->debug("--> SetPowerstate: " . $RequestedPowerState . "\n");
	
	#if( $PowerState{$client} == 1){
	
	if( $RequestedPowerState == 1){
		TurnPowerOn($client);
	}
	else{
		TurnPowerOff($client);
	}
	
	# my $srvAddress = "HTTP://" . $cprefs->get('srvAddress');
	# my $sMode = $request->getParam('_surroundMode'); #surround mode index
	# my $sOldMode = $request->getParam('_oldSurroundMode'); #old surround mode index
	# if ($sMode != $sOldMode) { #change the value

	#Slim::Control::Jive::refreshPluginMenus($client);
	
	# }
	$request->setStatusDone();
	
	#Slim::Control::Request::executeRequest( $client, [ 'SBNetIO_TopMenu' ] ); 
}


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


# # ----------------------------------------------------------------------------
# # external volume indication support code
# # used by iPeng and other controllers
# sub getexternalvolumeinfoCLI {
	# my @args = @_;
	# &reportOnOurPlayers();
	# if ( defined($getexternalvolumeinfoCoderef) ) {
		# # chain to the next implementation
		# return &$getexternalvolumeinfoCoderef(@args);
	# }
	# # else we're authoritative
	# my $request = $args[0];
	# $request->setStatusDone();
# }

# # ----------------------------------------------------------------------------
# sub reportOnOurPlayers() {
	# # loop through all currently attached players
	# foreach my $client (Slim::Player::Client::clients()) {
		# if (&usingSBNetIO($client) ) {
			# # using our volume control, report on our capabilities
			# $log->debug("Note that ".$client->name()." uses us for external volume control");
			# Slim::Control::Request::notifyFromArray($client, ['getexternalvolumeinfo', 0,   1,   string(&getDisplayName())]);
# #			Slim::Control::Request::notifyFromArray($client, ['getexternalvolumeinfo', 'relative:0', 'precise:1', 'plugin:SBNetIO']);
			# # precise:1		can set exact volume
			# # relative:1		can make relative volume changes
			# # plugin:DenonSerial	this plugin's name
		# }
	# }
# }
	
# --------------------------------------- external volume indication code -------------------------------
# end with something for plugin to do
1;
