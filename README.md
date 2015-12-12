# crontab.lua
lua crontab

参考资料：
* http://www.cise.ufl.edu/~cop4600/cgi-bin/lxr/http/source.cgi/commands/simple/cron.c
* https://github.com/kikito/cron.lua

中文使用说明
* http://www.cnblogs.com/linbc/p/4299065.html


-------------------------------------------------------------------------------------------------------
--传说中的测试代码



function RunTests()
	
	
	-- the following calls are equivalent
	function printMessage(a )
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
