#!/usr/bin/env ruby

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
