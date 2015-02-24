
--------------------------------------------
--任何一个记录产生一个实例
local Clock = {}
local Clock_mt = {__index = Clock}

local function __checkPositiveInteger(name, value)
	if type(value) ~= "number" or value < 0 then
		error(name .. " must be a positive number")
	end
end

--验证是否可执行
local function __isCallable(callback)
	local tc = type(callback)
	if tc == 'function' then return true end
	if tc == 'table' then
		local mt = getmetatable(callback)
		return type(mt) == 'table' and type(mt.__call) == 'function'
	end
	return false
end

local function newClock(cid, name, time, callback, update, args)
	assert(time)
	assert(callback)
	assert(__isCallable(callback), "callback must be a function")
	return setmetatable({
		cid		 = cid,
		name	 = name,
		time     = time,
		callback = callback,
		args     = args,
		running  = 0,
		update   = update
	}, Clock_mt)
end

function Clock:reset(running)
	running = running or 0
	__checkPositiveInteger('running', running)

	self.running = running
	self.deleted = nil			--如果已经删除的，也要复活
end

local function updateEveryClock(self, dt)
	__checkPositiveInteger('dt', dt)
	self.running = self.running + dt

	while self.running >= self.time do
		self.callback(unpack(self.args))
		self.running = self.running - self.time
	end
	return false
end

local function updateAfterClock(self, dt) -- returns true if expired
	__checkPositiveInteger('dt', dt)
	if self.running >= self.time then return true end

	self.running = self.running + dt

	if self.running >= self.time then
		self.callback(unpack(self.args))
		return true
	end
	return false
end

local function match( left, right )
	if left == '*' then return true end

	--单整数的情况
	if 'number' == type(left) and left == right then
		return true
	end

	--范围的情况 形如 1-12/5,算了,先不支持这种每隔几分钟的这种特性吧
	_,_,a,b = string.find(left, "(%d+)-(%d+)")
	if a and b then
		return (right >= tonumber(a) and right <= tonumber(b))
	end

	--多选项的情况 形如 1,2,3,4,5
	--哎,luajit不支持gfind,	
	--for d in string.gfind(left, "%d+") do
	--其实也可以for i in string.gmatch(left,'(%d+)') do
	local pos = 0
	for st,sp in function() return string.find(left, ',', pos, true) end do
		if tonumber(string.sub(left, pos, st - 1)) == right then
			return true
		end
		pos = sp + 1
	end
	return tonumber(string.sub(left, pos)) == right

	-- --找到第一个数字,然后看接下来的字符选择逻辑分支
	-- local st1,st2,pos = string.find(left, "-"), string.find(left, ","),0
	-- if st1 then
	-- 	local first,second = tonumber(string.sub(left, 0, st1 - 1)), 0
	-- 	if first < right then
	-- 		return false
	-- 	end
	-- 	local st2 = string.find(left, "/")
	-- 	if st2 then		--形如：12-23/5
	-- 		second = tonumber(string.sub(left, st1, st2 - 1))
	-- 		three = tonumber(string.sub(left, st2))
	-- 	else			--如：1-12
	-- 		second = tonumber(string.sub(left, st1))
	-- 	end
	-- 	if second < right then
	-- 		return false
	-- 	end
	-- else if st2 then
	-- 	--用','分割
	-- 	local pos,arr = st2+1, {}
	--     -- for each divider found
	--     for st,sp in function() return string.find(left, ',', pos, true) end do
	--         if tonumber(string.sub(left, pos, st - 1)) == right then
	--         	return true
	--         end
	--         pos = sp + 1
	--     end
	-- else
	-- 	return right == tonumber(string.sub(left, 0, st1 - 1))
	-- end
end

local function updateCrontab( self, dt )
	local now = os.date('*t')
	local tm = self.time
	--print('updateCrontab/now:',	now.min, now.hour,	now.day,	now.month,	now.wday)
	--print('updateCrontab/tm', tm.mn, tm.hr, tm.day, tm.mon, tm.wkd)
	--print('match:',match(tm.mn, now.min), match(tm.hr, now.hour), match(tm.day, now.day), match(tm.mon, now.month), match(tm.wkd, now.wday))
	if match(tm.mn, now.min) and match(tm.hr, now.hour)
		and match(tm.day, now.day) and match(tm.mon, now.month)
		and match(tm.wkd, now.wday)
	then
		--print('matching',self.name,self.callback,self.running)
		self.callback(unpack(self.args))
		self.running = self.running + 1
	end
	return false
end

--遍历并执行所有的定时器
local function updateClockTables( tbl )
	for i = #tbl, 1, -1 do
		local v = tbl[i]
		if v.deleted == true or v:update(1) then
			table.remove(tbl,i)
		end
	end
end

----------------------------------------------------------

local crontab = {}
crontab.__index = crontab

function crontab.new( obj )
	local obj = obj or {}
	setmetatable(obj, crontab)
	--执行一下构造函数
	if obj.ctor then
		obj.ctor(obj)
	end
 	return obj
end

function crontab:ctor(  )
	--所有的定时器
	self._clocks = self._clocks or {}
	self._crons = self._crons or {}
	--累积的时间差
	self._diff = self._diff or 0
	--已命名的定时器,设置为弱引用表
	self._nameObj = {}
	setmetatable(self._nameObj, {__mode="k,v"})

	--取得现在的秒数，延迟到整点分钟的时候启动一个定时
	self:after("__delayUpdateCrontab", 60-os.time()%60, function ( )
		--在整点分钟的时候，每隔一分钟执行一次
		self:every("__updateCrontab", 60, function ( )					
			updateClockTables(self._crons)
		end)
	end)
end

function crontab:update( diff )
	self._diff = self._diff + diff
	while self._diff >= 1000 do
		--TODO:这里真让人纠结，要不要支持累积时间误差呢？
		self._diff = self._diff - 1000
		--开始对所有的定时器心跳,如果返回true,则从列表中移除
		updateClockTables(self._clocks)
	end
end

function crontab:remove( name )
	if name and self._nameObj[name] then
		self._nameObj[name].deleted = true
	end
end

--通过判断callback的真正位置，以及参数类型来支持可变参数
--返回值顺序 number, string, number, function, args
--总的有如下5种情况
--1) cid,name,time,callback,args
--2) name,cid,time,callback,args
--3) name,time,callback,args
--4) cid,time,callback,args
--5) time,callback,args
local function changeParamsName( p1, p2, p3, p4, p5 )
	if __isCallable(p4) then
		if type(p1) == 'string' then
			return p2,p1,p3,p4,p5
		else
			return p1,p2,p3,p4,p5
		end
	elseif __isCallable(p3) then
		if type(p1) == 'string' then
			return nil,p1,p2,p3,p4
		else
			return p1,nil,p2,p3,p4
		end
	else
		return nil,nil,p1,p2,p3
	end
end

function crontab:every( cid, name, time, callback, args )
	--支持可变参数
	cid, name, time, callback, args = changeParamsName(cid, name, time, callback,args)
	__checkPositiveInteger('time', time)
	local clock = newClock(cid, name, time, callback, updateEveryClock, args or {})
	table.insert(self._clocks,clock)
	if name and name ~= '' then
		self._nameObj[name] = clock
	end
	return clock
end

function crontab:after( cid, name, time, callback, args )
	cid, name, time, callback, args = changeParamsName(cid, name, time, callback,args)
	__checkPositiveInteger('time', time)
	local clock = newClock(cid, name, time, callback, updateAfterClock, args or {})
	table.insert(self._clocks,clock)
	if name and name ~= '' then
		self._nameObj[name] = clock
	end
	return clock
end

--增加计划任务,精度到达分钟级别
--表达式：分钟[0-59] 小时[0-23] 每月的几号[1-31] 月份[1-12] 星期几[1-7]
--			星期天为1，
--			"*"代表所有的取值范围内的数字
--			"-"代表从某个数字到某个数字
--			"/"代表每的意思，如"*/5"表示每5个单位,未实现
--			","分散的数字
--	如："45 4-23/5 1,10,22 * *"
function crontab:addCron(cid, name, crontab_str, callback, args )
	cid, name, crontab_str, callback, args = changeParamsName(cid, name, crontab_str, callback, args)
	--print(cid, name, crontab_str, callback)
	local t = {}
	for v in string.gmatch(crontab_str,'[%w._/,%-*]+') do
		--如果可以转成整型直接转了，等下直接对比
		local i = tonumber(v)
		table.insert(t, i and i or v)
	end
	if table.getn(t) ~= 5 then
		return error(string.format('crontab string,[%s] error!',crontab_str))
	end

	local time = {mn = t[1], hr = t[2], day = t[3], mon = t[4], wkd = t[5]}
	local clock = newClock(cid, name, time, callback, updateCrontab, args or {})
	table.insert(self._crons,clock)
	if name and name ~= '' then
		self._nameObj[name] = clock
	end
end

--传说中的测试代码
local function RunTests()
	-- the following calls are equivalent:
	local function printMessage(a )
	  print('Hello',a)
	end

	local cron = crontab.new()

	local c1 = cron:after( 5, printMessage)
	local c2 = cron:after( 5, print, {'Hello'})

	c1:update(2) -- will print nothing, the action is not done yet
	c1:update(5) -- will print 'Hello' once

	c1:reset() -- reset the counter to 0

	-- prints 'hey' 5 times and then prints 'hello'
	while not c1:update(1) do
	  print('hey')
	end

	-- Create a periodical clock:
	local c3 = cron:every( 10, printMessage)

	c3:update(5) -- nothing (total time: 5)
	c3:update(4) -- nothing (total time: 9)
	c3:update(12) -- prints 'Hello' twice (total time is now 21)

	-------------------------------------
	c1.deleted = true
	c2.deleted = true
	c3.deleted = true

	------------------------------
	--测试一下match
	print('----------------------------------')
	assert(match('*',14) == true)
	assert(match('12-15',14) == true)
	assert(match('18-21',14) == false)
	assert(match('18,21',14) == false)
	assert(match('18,21,14',14) == true)

	--加一个定时器1分钟后执行
	cron:update(1000)

	--加入一个定时器每分钟执行
	cron:addCron('每秒执行', '* * * * *', print, {'.......... cron'})

	cron:update((60-os.time()%60)*1000)
	cron:update(30*1000)
	cron:update(31*1000)
	cron:update(1)
	cron:update(60*1000)		--打印两次
end

return crontab
