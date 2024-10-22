# StatsD compatible service to collect system stats

This service is intended to collect some metrics from host system and send them to StatsD compatible server.

## Service uses libraries:
- [simple StatsD client](https://github.com/Q-Master/statsdclient.nim")
- [systemd notify library](https://github.com/FedericoCeratto/nim-sdnotify)

## Currently collected metrics:

- system
  - hostname
  - uptime
- memory
  - total
  - free
  - available
  - cached
  - buffers
  - swap total
  - swap free
- cpu
  - total
  - idle
  - cpu load in percent
- disk
  - available
  - total
- network
  - in
  - out
- temperature (if available)
  - cpu
  - nvme

## Configuring the daemon
Daemon is supporting the ini format config.
Filename is **sysmon-statsd.ini** and mignt be placed either in `/etc` or in `~/.config/` or near the executable. 

### example:
```ini
statsd = "127.0.0.1:8125"
update-interval = 10
```

### supported parameters:
| Parameter name | Description | Default value |
|:--------------:|:------------|:--------------:|
| statsd | UDP address to send data to StatsD-compatible service | 127.0.0.1:8125 |
| update-interval | interval in seconds to query RMQ for updates | 30 |


## Building and installation
To build this daemon you need to install nim toolchain see [Nim installation](https://nim-lang.org/install.html).

### Manual building
To build daemon you should use

**Debug mode**
```bash
nimble build
```

**Release mode**
```bash
nimble build -d:release -l:"-flto" -t:"-flto" --opt:size --threads:on
objcopy --strip-all -R .comment -R .comments  sysmon-statsd
```

### SystemD service
The is a working systemd service file for the sysmon-statsd service. It searches binary at `/usr/local/bin/`.