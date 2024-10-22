# Package

version       = "0.1.0"
author        = "Vladimir Berezenko"
description   = "System monitor with sending data to statsd"
license       = "MIT"
srcDir        = "src"
namedBin["sysmon_statsd"] = "sysmon-statsd"

# Dependencies

requires "nim >= 2.2.0"
requires "simplestatsdclient >= 0.1.0"
requires "sdnotify"
