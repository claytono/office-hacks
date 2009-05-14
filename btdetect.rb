#!/usr/bin/env ruby

# The basic idea is that I want the lights at my desk to come on if
# I'm there, and turn off if I'm not.  This saves some power, but also
# keeps the janitors from turning off my lights and requiring me to
# turn them on by hand each morning.
#
# The way this works is that the BT MAC address for my phone and MBP
# are configured below.  It uses the l2ping program to issue a layer 2
# ping to each of these to determine if they're within range.  If
# either of them are found, then the assumption is that I'm at my
# desk, and the lights are turned on.  If both are missing, then the
# assumption is that I'm not at my desk, and the lights are turned
# off.
#
# For each device I can configure how often to try to ping it based on
# whether or not the device was present or not last time we tested.
# This is so that when my phone is in range, I'm not pinging it every
# second and killing the battery.
#
# To turn the lights on and off, I use an X10 controller with each of
# the 3 lights plugged into it, and the "br" program to control the
# X10 device.  I originally tried using the rubygem x10-cm17a, but
# found it to be unreliable.
#
# The reason I'm using l2ping instead of something like hcitool is
# that hcitool uses the caches that bluetoothd maintains, and I
# couldn't figure out a good way to turn off the caches, or configure
# how long items lived in the caches.  Also, l2ping returns a response
# much faster than hcitool does for uncached entries.  Using an
# ancient D-link USB BT dongle, it takes about 1-1.5 seconds to get
# setup, and then 1 second per ping.
#
# This is all pretty gross and has too much stuff hard coded, but it
# was a quick and dirty hack.

require 'rubygems'
require 'eventmachine'

DEBUG = 1
L2PING = "/usr/bin/sudo /usr/bin/l2ping"
BR = "/usr/bin/br"
X10DEV = "/dev/ttyUSB0"
X10ADDRESS = "3"


macs = {
  '00:1D:4F:8C:34:CE' => {
    :name => 'jezebel',
    :found => false,
    :missing_poll_time => 1,
    :found_poll_time => 30,
    :missing_time => 300,
    :last_seen => Time.now - 86400,
  },
  '00:21:E9:05:61:05' => {
    :name => 'iphone',
    :found => false,
    :missing_poll_time => 1,
    :found_poll_time => 300,
    :missing_time => 330,
    :last_seen => Time.now - 86400,
  }
}

class X10
  def self.on
    cmd = BR + " --port=" + X10DEV + " --on=" + X10ADDRESS
    puts "run: " + cmd
    system(cmd)
  end

  def self.off
    cmd = BR + " --port=" + X10DEV + " --off=" + X10ADDRESS
    puts "run: " + cmd
    system(cmd)
  end
end

class DeviceTracker
  @num_devices = 0
  def self.found
    if @num_devices == 0
      puts "turning on"
      X10.on
    end
    @num_devices += 1
    puts "#{@num_devices} found"
  end

  def self.lost
    @num_devices -= 1
    if @num_devices == 0
      puts "turning off"
      X10.off
    end
    puts "#{@num_devices} found"
  end
end

def check_available(mac, config)
  cmd = L2PING + " -c 1 " + mac
  puts "run: #{cmd}" if DEBUG
  IO.popen("#{cmd} 2>&1") do |io|
    io.each_line do |line|
      puts line if DEBUG
    end
  end

  elapsed = Time.now - config[:last_seen]
  retry_time = nil
  if $? == 0 # found
    if not config[:found]
      puts "Found #{config[:name]}, missing for #{elapsed} seconds"
      config[:found] = true
      DeviceTracker.found
    end
    config[:last_seen] = Time.now
    retry_time = config[:found_poll_time]
  else
    if Time.now - config[:last_seen] > config[:missing_time]
      if config[:found]
        config[:found] = false
        DeviceTracker.lost
      end
    end
    retry_time = config[:missing_poll_time]
  end
  EM::Timer.new(retry_time) do
    check_available(mac, config)
  end
end

EM.run {
  macs.each_pair { |mac, config| check_available(mac, config) }
}
