import std/[exitprocs, os, options]
import pkg/[simplestatsdclient, sdnotify]
import private/[config, procfs]


const SLEEP_TIME = 500


type
  Self = object
    config: SysMonStatsdConfig
    statsDM: StatsDClient
    sdM: SDNotify


var running: bool = true
var self {.threadVar.}: Self


proc atExit() {.noconv.} =
  running = false
  echo "Stopping application"


proc onTimerEvent() =
  try:
    let newInfo: FullInfo = fullInfo()
    let hostPart = "info." & newInfo.sys.hostname
    block:
      let memPart = hostPart & ".mem"
      self.statsDM.gauge(memPart & ".mem_total", newInfo.mem.memTotal)
      self.statsDM.gauge(memPart & ".mem_free", newInfo.mem.memFree)
      self.statsDM.gauge(memPart & ".mem_avail", newInfo.mem.memAvailable)
      self.statsDM.gauge(memPart & ".buffers", newInfo.mem.buffers)
      self.statsDM.gauge(memPart & ".cached", newInfo.mem.cached)
      self.statsDM.gauge(memPart & ".swap_total", newInfo.mem.swapTotal)
      self.statsDM.gauge(memPart & ".swap_free", newInfo.mem.swapFree)
    block:
      let cpuPart = hostPart & ".cpu"
      self.statsDM.gauge(cpuPart & ".total", newInfo.cpu.total)
      self.statsDM.gauge(cpuPart & ".idle", newInfo.cpu.idle)
      self.statsDM.gauge(cpuPart & ".cpu", newInfo.cpu.cpu)
      self.statsDM.gauge(cpuPart & ".la1", newInfo.cpu.la1)
      self.statsDM.gauge(cpuPart & ".la5", newInfo.cpu.la5)
      self.statsDM.gauge(cpuPart & ".la15", newInfo.cpu.la15)
    block:
      let diskPart = hostPart & ".disk"
      self.statsDM.gauge(diskPart & ".avail", newInfo.disk.avail)
      self.statsDM.gauge(diskPart & ".idle", newInfo.disk.total)
    block:
      let netPart = hostPart & ".net"
      self.statsDM.gauge(netPart & ".in", newInfo.net.netIn)
      self.statsDM.gauge(netPart & ".out", newInfo.net.netOut)
      self.statsDM.gauge(netPart & ".currin", newInfo.net.netInDiff)
      self.statsDM.gauge(netPart & ".currout", newInfo.net.netOutDiff)
    block:
      self.statsDM.gauge(hostPart & ".uptime", newInfo.sys.uptime)
    block:
      let tempPart = hostPart & ".temperature"
      if newInfo.temp.cpu.isSome:
        self.statsDM.gauge(tempPart & ".cpu", newInfo.temp.cpu.get)
      if newInfo.temp.nvme.isSome:
        self.statsDM.gauge(tempPart & ".nvme", newInfo.temp.nvme.get)
    self.statsDM.flush()
  except Exception as e:
    echo("Error getting info: " & e.msg)


proc initSelf(cfg: SysMonStatsdConfig): Self =
  result.config = cfg
  result.statsDM = newStatsDClient(cfg.statsdHost, cfg.statsdPort, buffered=true)
  try:
    result.sdM = newSDNotify()
    result.sdM.notify_ready()
  except:
    result.sdM = nil
  
proc main(cfg: SysMonStatsdConfig) =
  self = initSelf(cfg)
  initProcFS()
  var timeout = 0
  while running:
    sleep(SLEEP_TIME)
    timeout += SLEEP_TIME
    timeout = timeout.mod(self.config.updateInterval)
    if timeout == 0:
      onTimerEvent()
  if not self.sdM.isNil:
    self.sdM.notify_stopping()


when isMainModule:
  let cfg = readConfig()
  echo("Starting application")
  addExitProc(atExit)
  setControlCHook(atExit)
  main(cfg)