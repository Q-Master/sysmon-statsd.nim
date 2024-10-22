import std/[os, strutils, nativesockets, sets, strscans, options, net]
from posix import Uid, getpwuid
import sys


const PROCFS = "/proc"
const MIN_TEMP = -300000


type 
  ParseInfoError* = object of ValueError
    file*: string

  MemInfo* = ref MemInfoObject
  MemInfoObject* = object
    memTotal*: uint
    memFree*: uint
    memDiff*: int
    memAvailable*: uint
    buffers*: uint
    cached*: uint
    swapTotal*: uint
    swapFree*: uint

  CpuInfo* = ref CpuInfoObject
  CpuInfoObject* = object
    total*: uint
    idle*: uint
    cpu*: float

  SysInfo* = ref SysInfoObj
  SysInfoObj* = object
    hostname*: string
    uptimeHz*: uint

  Disk* = ref DiskObject
  DiskObject* = object
    avail*: uint
    total*: uint

  Net* = ref NetObject 
  NetObject* = object
    netIn*: uint
    netInDiff*: uint
    netOut*: uint
    netOutDiff*: uint

  Temp* = ref TempObject
  TempObject* = object
    cpu*: Option[float64]
    nvme*: Option[float64]

  FullInfo* = ref FullInfoObj
  FullInfoObj* = object
    sys*: SysInfo
    cpu*: CpuInfo
    mem*: MemInfo
    disk*: Disk
    net*: Net
    temp*: Temp


var prevInfo {.threadVar.}: FullInfo


proc fullInfo*(): FullInfo

proc initProcFS*() =
  prevInfo = fullInfo()
  sleep hz

proc newParseInfoError(file: string, parent: ref Exception): ref ParseInfoError =
  let parentMsg = if parent != nil: parent.msg else: "nil"
  var msg = "error during parsing " & file & ": " & parentMsg
  newException(ParseInfoError, msg, parent)


template catchErr(file: untyped, filename: string, body: untyped) =
  let file: string = filename
  try:
    body
  except CatchableError, Defect:
    raise newParseInfoError(file, getCurrentException())


proc checkedSub(a, b: uint): uint =
  if a > b:
    return a - b


proc checkedDiv(a, b: uint): float =
  if b != 0:
    return a.float / b.float


proc parseUptime(): uint =
  catchErr(file, PROCFS / "uptime"):
    let line = readLines(file, 1)[0]
    var f: float
    discard scanf(line, "$f", f)
    result = uint(float(hz) * f)


proc parseSize(str: string): uint =
  let normStr = str.strip(true, false)
  if normStr.endsWith(" kB"):
    1024 * parseUInt(normStr[0..^4])
  elif normStr.endsWith(" mB"):
    1024 * 1024 * parseUInt(normStr[0..^4])
  elif normStr.endsWith("B"):
    raise newException(ValueError, "cannot parse: " & normStr)
  else:
    parseUInt(normStr)


proc memInfo(): MemInfo =
  result.new
  catchErr(file, PROCFS / "meminfo"):
    for line in lines(file):
      let parts = line.split(":", 1)
      case parts[0]
      of "MemTotal": result.memTotal = parseSize(parts[1])
      of "MemFree": result.memFree = parseSize(parts[1])
      of "MemAvailable": result.memAvailable = parseSize(parts[1])
      of "Buffers": result.buffers = parseSize(parts[1])
      of "Cached": result.cached = parseSize(parts[1])
      of "SwapTotal": result.swapTotal = parseSize(parts[1])
      of "SwapFree": result.swapFree = parseSize(parts[1])
    result.memDiff = int(result.memFree) - (if prevInfo.isNil: 0 else: int(prevInfo.mem.memFree))


proc devName(s: string, o: var string, off: int): int =
  while off+result < s.len:
    let c = s[off+result]
    if not (c.isAlphaNumeric or c in "-_"):
      break
    o.add c
    inc result


proc parseStat(): CpuInfo =
  result.new
  catchErr(file, PROCFS / "stat"):
    var name: string
    var v1, v2, v3, v4, v5, v6, v7, v8: int

    for line in lines(file):
      if line.startsWith("cpu"):
        if scanf(line, "$w $s$i $i $i $i $i $i $i $i", name, v1, v2, v3, v4, v5, v6, v7, v8):
          let total = uint(v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8)
          let idle = uint(v4 + v5)
          if name == "cpu":
            let curTotal = checkedSub(total, (if prevInfo.isNil: 0.uint else: prevInfo.cpu.total))
            let curIdle = checkedSub(idle, (if prevInfo.isNil: 0.uint else: prevInfo.cpu.idle))
            let cpu = checkedDiv(100 * (curTotal - curIdle), curTotal)
            result = CpuInfo(total: total, idle: idle, cpu: cpu)
            break


proc sysInfo(): SysInfo =
  result.new
  result.hostname = getHostName()
  result.uptimeHz = parseUptime()


proc diskInfo(): Disk =
  result.new
  result.avail = 0
  result.total = 0
  var alreadyChecked: HashSet[string]
  catchErr(file, PROCFS / "mounts"):
    for line in lines(file):
      if line.startsWith("/dev/"):
        if line.startsWith("/dev/loop"):
          continue
        let parts = line.split(maxsplit = 2)
        let name = parts[0]
        if name in alreadyChecked:
          continue
        alreadyChecked.incl(name)
        let path = parts[1]
        var stat: Statvfs
        if statvfs(cstring path, stat) != 0:
          continue
        result.avail.inc(stat.f_bfree * stat.f_bsize)
        result.total.inc(stat.f_blocks * stat.f_bsize)
  return result


proc netInfo(): Net =
  result.new
  result.netIn = 0
  result.netOut = 0
  catchErr(file, PROCFS / "net/dev"):
    var i = 0
    for line in lines(file):
      inc i
      if i in 1..2:
        continue
      var name: string
      var tmp, netIn, netOut: int
      if not scanf(line, "$s${devName}:$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i",
          name, netIn, tmp, tmp, tmp, tmp, tmp, tmp, tmp, netOut):
        continue
      if name.startsWith("veth"):
        continue
      if name.startsWith("lo"):
        continue
      if name.startsWith("docker"):
        continue
      if name.startsWith("br-"):
        continue
      result.netIn += netIn.uint
      result.netOut += netOut.uint
      result.netInDiff = checkedSub(netIn.uint, (if prevInfo.isNil: 0.uint else: prevInfo.net.netIn))
      result.netOutDiff = checkedSub(netOut.uint, (if prevInfo.isNil: 0.uint else: prevInfo.net.netOut))


proc findMaxTemp(dir: string): Option[float64] =
  var maxTemp = MIN_TEMP
  for file in walkFiles(dir /../ "temp*_input"):
    for line in lines(file):
      let temp = parseInt(line)
      if temp > maxTemp:
        maxTemp = temp
      break
  if maxTemp != MIN_TEMP:
    return some(maxTemp / 1000)


proc tempInfo(): Temp =
  result.new
  var cnt = 0
  for file in walkFiles("/sys/class/hwmon/hwmon*/name"):
    case readFile(file)
    of "coretemp\n", "k10temp\n":
      result.cpu = findMaxTemp(file)
      cnt.inc
      if cnt == 2: break
    of "nvme\n":
      result.nvme = findMaxTemp(file)
      cnt.inc
      if cnt == 2: break
    else:
      discard


proc fullInfo*(): FullInfo =
  result.new
  result.sys = sysInfo()
  result.cpu = parseStat()
  result.mem = memInfo()
  result.disk = diskInfo()
  result.net = netInfo()
  result.temp = tempInfo()
  prevInfo = result
