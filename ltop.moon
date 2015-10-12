#!/usr/bin/env moon

socket = require "socket"


--  Basic interface functions


sh = ( string ) -> [line for line in (io.popen string)\lines!]


wmic = ( alias, key ) ->
    for line in *sh string.format "wmic %s get %s", alias, key
        if not string.match (string.lower line), key
            return string.gsub line, "%s", " "


--  Information functions

each = (funct, arr) ->
	return for _, v in pairs arr
		funct v

getuptime = ->
	file = (io.open "/proc/uptime")

	{days, hours, mins, secs} = (
		(arr) ->
			return for _, v in pairs arr
				tonumber v
	) { string.match (os.date "!%j %H %M %S",
			tonumber file\read!\match "([%d]+)"
		), "(.+) (.+) (.+) (.+)" }
	
	file\close!
	days -= 1
	
	:days, :hours, :mins, :secs


getmemory = ->
	pattern = "(%w+):%s+(%d+)"
	info = {line\match pattern for line in (io.open "/proc/meminfo")\lines!}
	mem = (info["MemTotal"] - info["MemFree"]) / info["MemTotal"] * 100
	swap = (info["SwapTotal"] - info["SwapFree"]) / info["SwapTotal"] * 100
	mem, swap


getcpu = ->
	--  55834515 0        26456436   470465796
	--  user (1) nice (2) system (3) idle (4)
	--  used = 1 + 3; total = 1 + 3 + 4
	usage = 
		cpu:  [1]: {}, [2]: {}
		cpu0: [1]: {}, [2]: {}
		cpu1: [1]: {}, [2]: {}

	for i = 1, 2
		for line in (io.open "/proc/stat")\lines!
			ms = [l for l in line\gmatch "[^%s]+"]
			if ms[1]\match "cpu"
				usage[ms[1]][i] = [m for m in *ms[2,]]
		socket.sleep 1 if i == 1

	return for k, v in pairs usage
		--  o: old; n: new; du: usage change; dt: total change
		o, n = v[1], v[2]
		du = (o[1] + o[3]) - (n[1] + n[3])
		dt = (o[1] + o[3] + o[4]) - (n[1] + n[3] + n[4])
		
		du / dt * 100


getwifi = ->
	return do
		local matches
		do
			query = sh "netsh wlan show interfaces"
			matches = [l for l in *query when l\match "Signal"]
		tonumber string.match (matches[1] or ""), ":%s+(%d+)%%"


getstates = ->
	return do
		s, r = 0, 0
		for line in *sh "procps o state"
			switch line
				when "S" then s += 1
				when "R" then r += 1
		{ :s, :r }


--  Graphs


-- Translated from http://stackoverflow.com/questions/7983574/#answer-26071044
utf8 = (decimal) ->
	return string.char decimal if decimal < 128
	charbytes = {}
	for bytes, vals in ipairs { {0x7FF, 192}, {0xFFFF, 224}, {0x1FFFFF, 240} }
		if decimal <= vals[1]
			for b = bytes + 1, 2, -1
				mod = decimal % 64
				decimal = (decimal - mod) / 64
				charbytes[b] = string.char 128 + mod
			charbytes[1] = string.char vals[2] + decimal
			break
	return table.concat charbytes


genm = (x, y, val) ->
	return for y = 1, y
		[val for x = 1, x]


m2b = (m) ->
	my, mx = #m, #m[1]
	cm = genm (math.ceil mx / 2), (math.ceil my / 4), " "
	cy, cx = #cm, #cm[1]
	for y = 1, cy
		for x = 1, cx
			n = 0x2800
			bm = {
				{ 0x01, 0x08 },
				{ 0x02, 0x10 },
				{ 0x04, 0x20 },
				{ 0x40, 0x80 }
			}
			for by = 1, 4
				for bx = 1, 2
					n += m[((y - 1) * 4) + by][((x - 1) * 2) + bx] and bm[by][bx] or 0x00
			cm[y][x] = utf8 n
	return for _, y in pairs cm
		(table.concat y)\gsub (utf8 0x2800), " "
				

graphm = (matrix, array) ->
	for a = #array, 1, -1
		v = array[a]
		for y = 1, math.min v * #matrix + 0.5
			matrix[#matrix - y + 1][#matrix[1] - (#array - a)] = true
	matrix


--  Meat


genbar = (perc) ->
	perc = math.min perc, 100
	figure = (tostring (math.floor perc * 10 + 0.5)/10) .. "%"
	perc /= 100

	bar = (("|"\rep (math.floor perc * 35 + 0.5)) .. (" "\rep 35))\sub 1, 35
	bar = ((bar\sub 1, 35 - figure\len!)  .. figure)
	
	smart = (math.max (35 - figure\len!), (math.floor perc * 35 + 0.5)) + 1

	s1 = bar\sub 1, 20
	s2 = bar\sub 21, 30
	s3 = bar\sub 31, smart - 1
	s4 = bar\sub smart

	table.concat {
		"\027[0;32m" .. s1
		"\027[0;33m" .. s2
		"\027[0;31m" .. s3
		"\027[1;30m" .. s4
	}

cpupast, mempast = {}, {}

stats = ->
	uptime, cpu, states, wifi = getuptime!, getcpu!, getstates!, getwifi!
	mem, swap = getmemory!

	wifi = 0 if not wifi

	table.insert cpupast, cpu[1] / 100
	table.insert mempast, mem / 100

	for _, v in pairs {cpupast, mempast}
		if #v == 61
			for i = 1, 60
				v[i] = v[i + 1]
			v[61] = nil

	struct = {
		"\027[1;34m       0 \027[1;37m[%s\027[1;37m]  \027[0;36mTasks:  "
		"\027[1;34m       1 \027[1;37m[%s\027[1;37m]  \027[0;36mWiFi:   "
		"\027[1;31m  Memory \027[1;37m[%s\027[1;37m]  \027[0;36mUptime: "
		"\027[0;36m    Swap \027[1;37m[%s\027[1;37m]"
	}

	bars = { (genbar cpu[2]), (genbar cpu[3]), (genbar mem), (genbar swap) }

	info = {
		(table.concat {
			"\027[1;36m%s\027[0;36m; "
			"\027[1;36m%s \027[0;36msleeping, "
			"\027[1;32m%s \027[0;36mrunning"
		})\format states.r + states.s, states.s, states.r,
		"\027[1;37m" .. wifi .. "\027[0;37m%",
		"\027[1;36m" .. string.format "%s day%s %s hour%s %s min%s %s sec%s",
			uptime.days,   (uptime.days == 1 and "" or "s"),
			uptime.hours,  (uptime.hours == 1 and "" or "s"),
			uptime.mins,   (uptime.mins == 1 and "" or "s"),
			uptime.secs,   (uptime.secs == 1 and "" or "s")
	}

	for k, v in pairs struct
		line = (v\format bars[k]) .. (info[k] or "")
		line ..= " "\rep 90 - (line\gsub "\027%[[%d;]+m", "")\len!
		print line

	cpugraph, memgraph = (genm 60, 32, false), (genm 60, 32, false)
	cpugraph = graphm cpugraph, cpupast
	memgraph = graphm memgraph, mempast

	cpub, memb = (m2b cpugraph), (m2b memgraph)

	io.write "\n"

	for y = 1, #cpub
		(y == #cpub and io.write or print) string.format "\027[1;34m  %s  \027[1;31m  %s", cpub[y], memb[y]

io.write "\027[2J\027[?25l"

while true
	io.write("\027[0;0H\n")
	stats!