#!/usr/bin/perl

use warnings;
use strict;
use Device::Modbus::TCP::Client;
use Device::Modbus;
use Data::Dumper;

my $client = Device::Modbus::TCP::Client->new(
    host => '10.60.X.Y',
);
 
sub getSerial {
	
	my $c = shift @_;
	my $req = $$c->read_holding_registers(
    	unit     => 1,
   		address  => 0xE0C0,
    	quantity => 4
	);

	$$c->send_request($req) || die "Send error: $!";
	
	my $response = $$c->receive_response;
	my $vs = \$response->values;
	my $s = '';
	my @d;
	my $count = 0;
	
	foreach(@{$$vs}) {

		# Convert Big endian to Little endian
		my $h = sprintf('%X', $_);
	
		if($h =~ m/^([[:xdigit:]]{2})([[:xdigit:]]{2})$/g) {
			push(@d, sprintf('%d', hex($2)));
			push(@d, sprintf('%d', hex($1)));
	
		}

	}	
	
	my $new_vs = join("", map { chr($_) } @d);
	print "Serial No: $new_vs\n";

}

#------------------------------------------------
# 
# Grabs values 0x0018 to 0x0022
#
#------------------------------------------------
sub getBatt {

	my $c = shift @_;
	##
	# Collect the Voltage/Current Scaling values
	##
	my $reqX = $$c->read_holding_registers(
    	unit     => 1,
   		address  => 0x0000,
    	quantity => 4
	);

	$$c->send_request($reqX) || die "Send error: $!";
	my $responseX = $$c->receive_response;
	my $V_PU_hi = int($responseX->{'message'}->{'values'}->[0]);
	my $V_PU_lo = int($responseX->{'message'}->{'values'}->[1]);
	my $I_PU_hi = int($responseX->{'message'}->{'values'}->[2]);
	my $I_PU_lo = int($responseX->{'message'}->{'values'}->[3]);

	my $fractional_term = $V_PU_lo / (2**16);
	my $I_fractional_term = $I_PU_lo / (2**16);
	
	#print "V_PU hi is $V_PU_hi\n";
	#print "V_PU lo is $V_PU_lo\n";
	#print "I_PU hi is $I_PU_hi\n";
	#print "I_PU lo is $I_PU_lo\n";
	
	##
	# Collect the voltage values
	##
	my $reqY = $$c->read_input_registers(
    	unit     => 1,
   		address  => 0x0018,
    	quantity => 16
	);

	$$c->send_request($reqY) || die "Send error: $!";
	my $responseY = $$c->receive_response;

	##
	# Collect MPPT values
	##

	my $reqZ = $$c->read_holding_registers(
    	unit     => 1,
   		address  => 0x003A,
    	quantity => 5
	);

	$$c->send_request($reqZ) || die "Send error: $!";
	my $responseZ = $$c->receive_response;

	my $xs = \$responseZ->values;
	my $power_out_shadow = sprintf("%.2f", $$xs->[0] * ($fractional_term + $V_PU_hi) * ($I_fractional_term + $I_PU_hi) * 2**(-17));
	my $power_in_shadow = sprintf("%.2f", $$xs->[1] * ($fractional_term + $V_PU_hi) * ($I_fractional_term + $I_PU_hi) * 2**(-17));
	my $sweep_Pin_max = sprintf("%.2f", $$xs->[2] * ($fractional_term + $V_PU_hi) * ($I_fractional_term + $I_PU_hi) * 2**(-17));
	my $sweep_vmp = sprintf("%.2f", unpack("s", pack("s", $$xs->[3])) * ($fractional_term + $V_PU_hi) * 2**(-15));
	my $sweep_voc = sprintf("%.2f", unpack("s", pack("s", $$xs->[4])) * ($fractional_term + $V_PU_hi) * 2**(-15));

	print "MPPT Output Power(W):.........$power_out_shadow\n";
	print "MPPT Input Power(W):..........$power_in_shadow\n";
	print "MPPT Max Power of Last Sweep:.$sweep_Pin_max\n";
	print "MPPT Sweep Vmp:...............$sweep_vmp\n";
	print "MPPT Sweep Voc:...............$sweep_voc\n";

	##
	# Collect Charger Values
	##

	my $reqC = $$c->read_holding_registers(
    	unit     => 1,
   		address  => 0x0032,
    	quantity => 8
	);
	
	$$c->send_request($reqC) || die "Send error: $!";
	my $responseC = $$c->receive_response;

	my $xc = \$responseC->values;
	my $vb_ref = sprintf("%.2f", unpack("s", pack("s", $$xc->[1])) * ($fractional_term + $V_PU_hi) * 2**(-15));
	my @chargeState = (
		"START",		# 0
		"NIGHT CHECK",	# 1
		"DISCONNECT",	# 2
		"NIGHT",		# 3
		"FAULT",		# 4
		"MPPT",			# 5
		"ABSORPTION",	# 6
		"FLOAT",		# 7
		"EQUALIZE",		# 8
		"SLAVE"			# 9
	);
	print "Charge State:.................".$chargeState[$$xc->[0]]."\n";
	print "Target Voltage(V):............$vb_ref\n";
	
	#
	# Using pack/unpack to take decimal value from ModBus::Client
	# and convert into 2 byte scalar as a 'signed' 16 bytes (e.g. 0xFF really means -32767, not 65535).
	# unpack returns as a string.
	# Except in case of temperatures; they're 8 bit signed integer (-127 to +127)

	my $vs = \$responseY->values;
	my $adc_vb_f_med = sprintf("%.2f", unpack("s", pack("s", $$vs->[0])) * ($fractional_term + $V_PU_hi) * 2**(-15));
	my $adc_vbterm_f = sprintf("%.2f", unpack("s", pack("s", $$vs->[1])) * ($fractional_term + $V_PU_hi) * 2**(-15));
	my $adc_va_f = sprintf("%.2f", unpack("s", pack("s", $$vs->[3])) * ($fractional_term + $V_PU_hi) * 2**(-15));
	my $adc_ib_f_shadow = sprintf("%.2f", unpack("s", pack("s", $$vs->[4])) * ($I_fractional_term + $I_PU_hi) * 2**(-15));
	my $adc_ia_f_shadow = sprintf("%.2f", unpack("s", pack("s", $$vs->[5])) * ($I_fractional_term + $I_PU_hi) * 2**(-15));
	my $adc_p12_f = sprintf("%.2f", unpack("s", pack("s", $$vs->[6])) * 18.612 * 2**(-15));
	my $adc_p3_f = sprintf("%.2f", unpack("s", pack("s", $$vs->[7])) * 6.6 * 2**(-15));
	my $adc_pmeter_f = sprintf("%.2f", unpack("s", pack("s", $$vs->[8])) * 18.612 * 2**(-15));
	my $adc_p18_f = sprintf("%.2f", unpack("s", pack("s", $$vs->[9])) * 3 * 2**(-15));
	my $adc_v_ref = sprintf("%.2f", unpack("s", pack("s", $$vs->[10])) * 3 * 2**(-15));
	my $T_hs = unpack("c", pack("c", $$vs->[11]));
	my $T_rts = unpack("c", pack("c", $$vs->[12]));
	my $T_batt = unpack("c", pack("c", $$vs->[13]));
	my $adc_vb_f_1m = sprintf("%.2f", unpack("s", pack("s", $$vs->[14])) * ($fractional_term + $V_PU_hi) * 2**(-15));
	my $adc_ib_f_1m = sprintf("%.2f", unpack("s", pack("s", $$vs->[15])) * ($I_fractional_term + $I_PU_hi) * 2**(-15));

	print "Battery Reg. Voltage(V):......$adc_vb_f_med\n";
	print "Battery Terminal Voltage(V):..$adc_vbterm_f\n";
	print "PV Terminal Voltage(V):.......$adc_va_f\n";
	print "Battery Current(A):...........$adc_ib_f_shadow\n";
	print "PV Current(A):................$adc_ib_f_shadow\n";
	print "12V Supply:...................$adc_p12_f\n";
	print "MeterBus Supply:..............$adc_pmeter_f\n";
	print "3V Supply:....................$adc_p3_f\n";
	print "1.8V Supply:..................$adc_p18_f\n";
	print "Reference Voltage:............$adc_v_ref\n";
	print "Heatsink Temperature:.........$T_hs\n";
	print "RTS Temperature:..............$T_rts\n";
	print "Battery Reg. Temperature:.....$T_batt\n";
	print "\n";
	print "Battery Voltage 1minute:......$adc_vb_f_1m\n";
	print "Charge Current 1minute:.......$adc_ib_f_1m\n";


}

sub getAlarms {
	
	my $c = shift @_;
	my $req = $$c->read_holding_registers(
    	unit     => 1,
   		address  => 0x002C,
    	quantity => 4
	);

	$$c->send_request($req) || die "Send error: $!";
	
	my $response = $$c->receive_response;
	my $vs = \$response->{'message'}->{'values'};
	
	# Compare decimal value from Modbus Client to Hex encoded representation
	# of the bit (e.g. 2^7 = 128Decimal = 80Hex)

	my @alarms = (
			"RTS OPEN                     ", # Bit  0 LSB of 2nd byte of register 0x002F
			"RTS SHORT                    ", # Bit  1
			"RTS DISCONNECTED             ", # Bit  2
			"HEATSINK TEMP SENSOR OPEN    ", # Bit  3
			"HEATSINK TEMP SENSOR SHORT   ", # Bit  4
			"HIGH TEMP CURRENT LIMIT      ", # Bit  5
			"CURRENT LIMIT                ", # Bit  6
			"CURRENT OFFSET               ", # Bit  7 MSB
			"BATTERY SENSE OUT OF RANGE   ", # Bit  8 LSB
			"BATTERY SENSE DISCONNECTED   ", # Bit  9
			"UNCALIBRATED                 ", # Bit 10
			"RTS MISWIRE                  ", # Bit 11
			"HIGH VOLTAGE DISCONNECT      ", # Bit 12
			"UNDEFINED                    ", # Bit 13
			"SYSTEM MISWIRE               ", # Bit 14
			"MOSFET OPEN                  ", # Bit 15 MSB of 1st byte of register 0x002F
			"P12 VOLTAGE OFF              ", # Bit 16 LSB of 2nd byte register 0x002E
			"HIGH INPUT VOLTAGE CURRENT   ", # Bit 17
			"ADC INPUT MAX                ", # Bit 18
			"CONTROLLER WAS RESET         ", # Bit 19
			"ALARM 21                     ", # Bit 20
			"ALARM 22                     ", # Bit 21
			"ALARM 23                     ", # Bit 22
			"ALARM 24                     "  # Bit 23 MSB
			);

	my @faults = (
			"OVERCURRENT                  ", # Bit  0
			"FETS SHORTED                 ", # Bit  1
			"SOFTWARE BUG                 ", # Bit  2
			"BATTERY HVD                  ", # Bit  3
			"ARRAY HVD                    ", # Bit  4 
			"SETTING SWITCH CHANGED       ", # Bit  5
			"CUSTOM SETTINGS EDIT         ", # Bit  6
			"RTS SHORTED                  ", # Bit  7
			"RTS DISCONNECTED             ", # Bit  8
			"EEPROM RETRY LIMIT           ", # Bit  9
			"RESERVED                     ", # Bit 10
			"SLAVE CONTROL TIMEOUT        ", # Bit 11
			"FAULT 13                     ", # Bit 12
			"FAULT 14                     ", # Bit 13
			"FAULT 15                     ", # Bit 14
			"FAULT 16                     "  # Bit 15
	);

	sub check_number {
    	my $number = shift;
		my $array = shift;
    	my $bitmask = 1; # will keep incrementing it by *2 every time
    		for(my $i=0; $i < @{$array}; $i++) {
        		my $match = $bitmask & $number ? "ON " : "OFF"; # is the bit flipped on?
        		print "|$match| $array->[$i] | \n";
        		#$bitmask *= 2; # or bit-shift - faster but less readable.
				$bitmask = $bitmask << 1;
    		}
	}

	print "\nALARMS:\n\n";
	check_number($$vs->[3], \@alarms);
	check_number($$vs->[2], \@alarms);

	print "\nFAULTS:\n\n";
	check_number($$vs->[0], \@faults);

	
}

sub getLogger {
	
	my $c = shift @_;
	my $req = $$c->read_holding_registers(
    	unit     => 1,
   		address  => 0x0040,
    	quantity => 16
	);

	$$c->send_request($req) || die "Send error: $!";
	
	my $response = $$c->receive_response;
	my $vs = \$response->values;
	my $s = '';
	my @d;
	my $count = 0;
	
	print Dumper $$vs;

}

getAlarms(\$client);
getSerial(\$client);
getBatt(\$client);
#getLogger(\$client);

$client->disconnect;

