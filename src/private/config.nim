import std/[parsecfg, os, strutils, nativesockets]

type
  SysMonStatsdConfig* = object
    statsdHost*: string
    statsdPort*: Port
    updateInterval*: int


proc initConfig(
  updateInterval: int = 10,
  statsd: string = "127.0.0.1:8125",
  ): SysMonStatsdConfig =
  var splits = statsd.rsplit(':', maxSplit=1)
  if splits.len == 1:
    result.statsdHost = splits[0]
    result.statsdPort = Port(8125)
  else:
    result.statsdHost = splits[0]
    result.statsdPort = Port(parseBiggestInt(splits[1]))
  result.updateInterval = updateInterval*1000

  echo "--- Current configuration ---"
  echo "StatsD ", result.statsdHost, ":", result.statsdPort
  echo "---"


proc readConfig*(): SysMonStatsdConfig =
  let configFilename = "sysmon-statsd.ini"
  var path: string
  for src in @["./", "~/.config/", "/etc"]:
    path = src / configFilename
    if fileExists(path):
      break
  try:
    let conf = loadConfig(path)
    result = initConfig(
      updateInterval = parseBiggestInt(conf.getSectionValue("", "update-interval", "30")),
      statsd = conf.getSectionValue("", "statsd", "127.0.0.1:8125"),
    )
  except IOError as e:
    echo "Error reading config (", e.msg, "). Using defaults."
    result = initConfig()