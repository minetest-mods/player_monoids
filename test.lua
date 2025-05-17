-- monoids.lua
-- This file defines a set of testing chatcommands for the monoids system.

local speed = player_monoids.speed
local jump = player_monoids.jump

minetest.register_privilege("monoid_master", {
	description = "Allows testing of player monoids.",
	give_to_singleplayer = false,
	give_to_admin = true,
})

--------------------------------------------------------------------------------
-- Helper: reset branches for both speed and jump
--------------------------------------------------------------------------------
local function reset_all_monoid_branches(player)
	local p_name = player:get_player_name()

	for _, monoid in ipairs({speed, jump}) do
		if monoid and monoid.player_map and monoid.player_map[p_name] then
			local pm = monoid.player_map[p_name]
			local to_delete = {}
			for bn, _ in pairs(pm.branches) do
				table.insert(to_delete, bn)
			end
			for _, bn in ipairs(to_delete) do
				local br = monoid:get_branch(bn)
				if br then
					br:reset(player)
					br:delete(player)
				end
			end
			monoid:get_branch("main")
			monoid:checkout_branch(player, "main")
		end
	end
end

--------------------------------------------------------------------------------
-- 1) Test Speed Add/Remove
--------------------------------------------------------------------------------
local function test_speed_add_remove(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local before = speed:value(player)
	local ch_id = speed:add_change(player, 10)
	local after_add = speed:value(player)

	if after_add == before then
		minetest.chat_send_player(p_name, "[Add/Remove] FAIL: no speed change.")
	else
		minetest.chat_send_player(p_name, "[Add/Remove] PASS: speed " .. before .. " -> " .. after_add)
	end

	minetest.after(2, function()
		local again = minetest.get_player_by_name(p_name)
		if not again then return end
		speed:del_change(again, ch_id)
		local after_del = speed:value(again)
		if math.abs(after_del - before) < 0.0001 then
			minetest.chat_send_player(p_name, "[Add/Remove] PASS: speed returned to " .. before)
		else
			minetest.chat_send_player(p_name, "[Add/Remove] FAIL: final " .. after_del .. " != initial " .. before)
		end
	end)
end

--------------------------------------------------------------------------------
-- 2) Test Branch Isolation
--------------------------------------------------------------------------------
local function test_branch_isolation(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local init = speed:value(player)
	speed:checkout_branch(player, "arena")
	speed:add_change(player, 0.5, "arena_slowdown", "arena")
	local arena_spd = speed:value(player)
	if arena_spd >= init then
		minetest.chat_send_player(p_name, "[BranchIsolation] FAIL: arena slowdown not effective.")
	else
		minetest.chat_send_player(p_name, "[BranchIsolation] PASS: arena slow " .. init .. " -> " .. arena_spd)
	end

	minetest.after(2, function()
		speed:checkout_branch(player, "main")
		speed:add_change(player, 2, "speed_boost")
		local main_spd = speed:value(player)
		if main_spd <= init then
			minetest.chat_send_player(p_name, "[BranchIsolation] FAIL: main speedup not effective.")
		else
			minetest.chat_send_player(p_name, "[BranchIsolation] PASS: main speed " .. init .. " -> " .. main_spd)
		end
	end)

	minetest.after(4, function()
		speed:checkout_branch(player, "arena")
		local arena2 = speed:value(player)
		minetest.chat_send_player(p_name, "[BranchIsolation] re-check => " .. arena2)
	end)
end

--------------------------------------------------------------------------------
-- 3) Test Branch Concurrent
--------------------------------------------------------------------------------
local function test_branch_concurrent(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local init = speed:value(player)

	local arena_branch = speed:checkout_branch(player, "arena")
	arena_branch:add_change(player, 0.5, "arena_slowdown")
	local arena_spd = speed:value(player)
	if arena_spd >= init then
		minetest.chat_send_player(p_name, "[BranchConcurrent] FAIL: arena slowdown didn't reduce speed.")
	else
		minetest.chat_send_player(p_name, "[BranchConcurrent] PASS: arena from " .. init .. " -> " .. arena_spd)
	end

	minetest.after(2, function()
		local mining_branch = speed:checkout_branch(player, "mining")
		if not mining_branch then
			minetest.chat_send_player(p_name, "[BranchConcurrent] FAIL: 'mining' branch could not be created.")
			return
		end
		mining_branch:add_change(player, 0.3, "mining_slowdown")

		local main_branch = speed:get_branch("main")
		if not main_branch then
			minetest.chat_send_player(p_name, "[BranchConcurrent] FAIL: 'main' branch doesn't exist?")
			return
		end
		main_branch:add_change(player, 2, "main_speedup_concurrent")

		local mining_spd = speed:value(player)
		local main_spd = main_branch:value(player)
		if mining_spd >= init then
			minetest.chat_send_player(p_name, "[BranchConcurrent] FAIL: mining slowdown not effective.")
		else
			minetest.chat_send_player(p_name, "[BranchConcurrent] PASS: mining slow => " .. mining_spd)
		end
		if main_spd <= init then
			minetest.chat_send_player(p_name, "[BranchConcurrent] FAIL: main concurrent speedup not effective.")
		else
			minetest.chat_send_player(p_name, "[BranchConcurrent] PASS: main speed => " .. main_spd)
		end
	end)

	minetest.after(4, function()
		local arena_b = speed:get_branch("arena")
		if arena_b then
			arena_b:reset(player)
			speed:checkout_branch(player, "arena")
			local reset_spd = speed:value(player)
			minetest.chat_send_player(p_name, "[BranchConcurrent] arena reset => " .. reset_spd)
		else
			minetest.chat_send_player(p_name, "[BranchConcurrent] FAIL: 'arena' branch not found?")
		end
	end)

	minetest.after(6, function()
		speed:checkout_branch(player, "main")
		local main_spd = speed:value(player)
		minetest.chat_send_player(p_name, "[BranchConcurrent] final main => " .. main_spd)
	end)
end

--------------------------------------------------------------------------------
-- 4) Test OnChange ListenAll
--------------------------------------------------------------------------------
local function test_onchange_listen_all(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local call_count = 0
	speed.def.listen_to_all_changes = true

	local old_on_change = speed.def.on_change
	speed.def.on_change = function(old, new, plyr, branch)
		call_count = call_count + 1
	end

	speed:add_change(player, 1, "active_change")
	speed:add_change(player, 0.5, "arena_slowdown", "arena")

	minetest.after(2, function()
		speed.def.on_change = old_on_change
		speed.def.listen_to_all_changes = false
		if call_count == 0 then
			minetest.chat_send_player(p_name, "[OnChangeAll] FAIL: on_change not triggered.")
		else
			minetest.chat_send_player(p_name, "[OnChangeAll] PASS: on_change called " .. call_count .. " times.")
		end
	end)
end

minetest.register_chatcommand("test_listen_all", {
	description = "Test on_change across all branches.",
	privs = {monoid_master = true},
	func = function(p_name)
		local player = minetest.get_player_by_name(p_name)
		if player then
			test_onchange_listen_all(player)
		end
	end,
})

--------------------------------------------------------------------------------
-- 5) Test OnChange ListenActive
--------------------------------------------------------------------------------
local function test_onchange_listen_active(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local call_count = 0
	speed.def.listen_to_all_changes = false

	local old_on_change = speed.def.on_change
	speed.def.on_change = function(old, new, plyr, branch)
		call_count = call_count + 1
	end

	speed:add_change(player, 1, "active_change")
	speed:add_change(player, 0.5, "arena_slowdown", "arena")

	minetest.after(2, function()
		speed.def.on_change = old_on_change
		speed.def.listen_to_all_changes = false
		if call_count == 0 then
			minetest.chat_send_player(p_name, "[OnChangeActive] FAIL: on_change not called.")
		else
			minetest.chat_send_player(p_name, "[OnChangeActive] PASS: on_change triggered " .. call_count .. " times.")
		end
	end)
end

minetest.register_chatcommand("test_listen_active", {
	description = "Test on_change only in active branch.",
	privs = {monoid_master = true},
	func = function(p_name)
		local player = minetest.get_player_by_name(p_name)
		if player then
			test_onchange_listen_active(player)
		end
	end,
})

--------------------------------------------------------------------------------
-- 6) Test BranchName
--------------------------------------------------------------------------------
local function test_branch_name_check(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	speed:checkout_branch(player, "arena")
	local branch = speed:get_branch("arena")
	if not branch then
		minetest.chat_send_player(p_name, "[BranchNameCheck] FAIL: get_branch('arena') is nil?")
		return
	end
	local got = branch:get_name()
	if got == "arena" then
		minetest.chat_send_player(p_name, "[BranchNameCheck] PASS: got 'arena'")
	else
		minetest.chat_send_player(p_name, "[BranchNameCheck] FAIL: expected 'arena', got '" .. (got or "nil") .. "'")
	end
end

minetest.register_chatcommand("test_branch_name", {
	description = "Test branch:get_name() method.",
	privs = {monoid_master = true},
	func = function(p_name)
		local player = minetest.get_player_by_name(p_name)
		if player then
			test_branch_name_check(player)
		end
	end,
})

--------------------------------------------------------------------------------
-- 7) Test ActiveBranchGet
--------------------------------------------------------------------------------
local function test_active_branch_check(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	speed:checkout_branch(player, "arena")
	local active = speed:get_active_branch(player)
	local got = active and active:get_name() or "(nil)"
	if got == "arena" then
		minetest.chat_send_player(p_name, "[ActiveBranchGet] PASS: 'arena' active")
	else
		minetest.chat_send_player(p_name, "[ActiveBranchGet] FAIL: expected 'arena', got '" .. got .. "'")
	end
end

minetest.register_chatcommand("test_active_branch", {
	description = "Test monoid:get_active_branch.",
	privs = {monoid_master = true},
	func = function(p_name)
		local player = minetest.get_player_by_name(p_name)
		if player then
			test_active_branch_check(player)
		end
	end,
})

--------------------------------------------------------------------------------
-- 8) Test BranchDelete
--------------------------------------------------------------------------------
local function test_branch_delete_check(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local main_branch = speed:get_branch("main")
	local before_main = main_branch:value(player)

	local del_branch = speed:checkout_branch(player, "delete_test")
	del_branch:add_change(player, 0.2, "delete_test_slowdown")
	local delete_spd = speed:value(player)

	if delete_spd == before_main then
		minetest.chat_send_player(p_name, "[BranchDelete] FAIL: no slowdown?")
	else
		minetest.chat_send_player(p_name, "[BranchDelete] PASS: speed from " .. before_main .. " to " .. delete_spd)
	end

	minetest.after(2, function()
		del_branch:delete(player)
		if speed.player_map[p_name].branches["delete_test"] then
			minetest.chat_send_player(p_name, "[BranchDelete] FAIL: branch still exists.")
		else
			local active_b = speed.player_map[p_name].active_branch
			local after_main = speed:value(player)
			if active_b ~= "main" then
				minetest.chat_send_player(p_name, "[BranchDelete] FAIL: active branch is " .. active_b)
			elseif math.abs(after_main - before_main) > 0.0001 then
				minetest.chat_send_player(p_name, "[BranchDelete] FAIL: main speed not restored.")
			else
				minetest.chat_send_player(p_name, "[BranchDelete] PASS: 'delete_test' gone, main restored.")
			end
		end
	end)
end

minetest.register_chatcommand("test_branch_delete_monoids", {
	description = "Runs a test on monoids branch deletion.",
	privs = {monoid_master = true},
	func = function(p_name)
		local player = minetest.get_player_by_name(p_name)
		if player then
			test_branch_delete_check(player)
		end
	end,
})

--------------------------------------------------------------------------------
-- 9) Test GetBranches
--------------------------------------------------------------------------------
local function test_get_branches(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local br_a = speed:checkout_branch(player, "testA")
	if br_a then
		br_a:add_change(player, 2, "testA_boost")
	else
		minetest.chat_send_player(p_name, "[GetBranches] FAIL: unable to create 'testA'.")
	end

	local br_b = speed:new_branch(player, "testB")
	if br_b then
		br_b:add_change(player, 0.3, "testB_slow")
	else
		minetest.chat_send_player(p_name, "[GetBranches] FAIL: new_branch('testB') returned nil.")
	end

	local br_map = speed:get_branches(player)
	if br_map["testA"] and br_map["testB"] then
		minetest.chat_send_player(p_name, "[GetBranches] PASS: 'testA' and 'testB' found.")
	else
		minetest.chat_send_player(p_name, "[GetBranches] FAIL: missing 'testA' or 'testB' in get_branches.")
	end
end

--------------------------------------------------------------------------------
-- 10) Test on_branch_created / on_branch_deleted
--------------------------------------------------------------------------------
local function test_on_branch_create_delete(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local created_count = 0
	local deleted_count = 0

	local old_on_branch_created = speed.def.on_branch_created
	local old_on_branch_deleted = speed.def.on_branch_deleted

	speed.def.on_branch_created = function(monoid, plyr, branch_name)
		created_count = created_count + 1
	end

	speed.def.on_branch_deleted = function(monoid, plyr, branch_name)
		deleted_count = deleted_count + 1
	end

	local new_branch = speed:checkout_branch(player, "my_new_branch")
	if not new_branch then
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] FAIL: checkout_branch returned nil.")
	else
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] Created 'my_new_branch'.")
	end

	local del_branch = speed:checkout_branch(player, "my_del_branch")
	if not del_branch then
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] FAIL: couldn't create 'my_del_branch'.")
	else
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] Created 'my_del_branch'. Deleting...")
		del_branch:delete(player)
	end

	if created_count == 0 then
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] FAIL: on_branch_created not called.")
	else
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] PASS: on_branch_created called " .. created_count .. " time(s).")
	end

	if deleted_count == 0 then
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] FAIL: on_branch_deleted not called.")
	else
		minetest.chat_send_player(p_name, "[OnBranchCreateDelete] PASS: on_branch_deleted called " .. deleted_count .. " time(s).")
	end

	speed.def.on_branch_created = old_on_branch_created
	speed.def.on_branch_deleted = old_on_branch_deleted
end

--------------------------------------------------------------------------------
-- 11) Test monoid:new_branch
--------------------------------------------------------------------------------
local function test_new_branch_method(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local init_speed = speed:value(player)

	local custom_branch = speed:new_branch(player, "custom_new_branch")
	if not custom_branch then
		minetest.chat_send_player(p_name, "[NewBranchMethod] FAIL: new_branch returned nil")
		return
	end
	custom_branch:add_change(player, 0.4, "custom_slow")

	local after_new = speed:value(player)
	if math.abs(after_new - init_speed) > 0.0001 then
		minetest.chat_send_player(p_name, "[NewBranchMethod] FAIL: Speed changed even though new branch not active.")
	else
		minetest.chat_send_player(p_name, "[NewBranchMethod] PASS: Speed unchanged = " .. after_new)
	end

	speed:checkout_branch(player, "custom_new_branch")
	local after_checkout = speed:value(player)
	if after_checkout == init_speed then
		minetest.chat_send_player(p_name, "[NewBranchMethod] FAIL: Speed not changed after activation.")
	else
		minetest.chat_send_player(p_name, "[NewBranchMethod] PASS: Speed changed from " .. init_speed .. " to " .. after_checkout)
	end
end

--------------------------------------------------------------------------------
-- 12) Test main branch cannot be deleted
--------------------------------------------------------------------------------
local function test_main_branch_cant_delete(player)
	local p_name = player:get_player_name()
	reset_all_monoid_branches(player)

	local main_br = speed:get_branch("main")
	if not main_br then
		minetest.chat_send_player(p_name, "[MainBranchCantDelete] FAIL: main branch does not exist?")
		return
	end

	main_br:delete(player)
	local still_main = speed.player_map[p_name] and speed.player_map[p_name].branches["main"]
	if still_main then
		minetest.chat_send_player(p_name, "[MainBranchCantDelete] PASS: main not deleted.")
	else
		minetest.chat_send_player(p_name, "[MainBranchCantDelete] FAIL: main branch was deleted!")
	end
end

--------------------------------------------------------------------------------
-- 13) Test using speed + jump together in the same branch
--------------------------------------------------------------------------------
local function test_speed_and_jump_together(player)
	local p_name = player:get_player_name()

	if not jump then
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] FAIL: 'player_monoids.jump' not defined!")
		return
	end

	reset_all_monoid_branches(player)

	-- Grab initial speed + jump
	local init_speed = speed:value(player)
	local init_jump = jump:value(player)

	-- Create or checkout a test branch that affects both
	speed:checkout_branch(player, "double_test")
	jump:checkout_branch(player, "double_test")

	local sp_ch_id = speed:add_change(player, 2, "double_spd", "double_test")
	local jp_ch_id = jump:add_change(player, 1.5, "double_jmp", "double_test")

	local after_speed = speed:value(player)
	local after_jump = jump:value(player)

	local speed_changed = after_speed ~= init_speed
	local jump_changed = after_jump ~= init_jump

	if speed_changed and jump_changed then
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] PASS: Speed changed " .. init_speed .. "->" .. after_speed .. ", Jump changed " .. init_jump .. "->" .. after_jump)
	else
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] FAIL: Speed changed=" .. tostring(speed_changed) .. ", Jump changed=" .. tostring(jump_changed))
	end

	-- Remove only speed change, see if jump remains.
	speed:del_change(player, sp_ch_id, "double_test")
	local sp2 = speed:value(player)
	local jp2 = jump:value(player)

	if math.abs(sp2 - init_speed) < 0.0001 and math.abs(jp2 - after_jump) < 0.0001 then
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] PASS: Speed reverted to " .. init_speed .. ", jump remains " .. jp2)
	else
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] FAIL: partial revert mismatch. Speed=" .. sp2 .. ", jump=" .. jp2)
	end

	-- Remove jump change, confirm both are back to init
	jump:del_change(player, jp_ch_id, "double_test")
	local sp3 = speed:value(player)
	local jp3 = jump:value(player)

	if math.abs(sp3 - init_speed) < 0.0001 and math.abs(jp3 - init_jump) < 0.0001 then
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] PASS: both speed/jump back to init.")
	else
		minetest.chat_send_player(p_name, "[SpeedJumpTogether] FAIL: final mismatch. Speed=" .. sp3 .. ", jump=" .. jp3)
	end
end

--------------------------------------------------------------------------------
-- 14) Test monoid:value() with or without a branch param
--     to confirm it uses the active branch if omitted.
--------------------------------------------------------------------------------
local function test_value_api(player)
	reset_all_monoid_branches(player)
	local p_name = player:get_player_name()

	local init_val = speed:value(player) -- active=main

	-- new branch and add a slowdown
	local br_test = speed:new_branch(player, "value_api_test")
	br_test:add_change(player, 0.5, "slower")
	-- the newly created branch is not active yet, so speed:value(player) remains init_val
	local current_active_val = speed:value(player)
	local named_branch_val = speed:value(player, "value_api_test")

	if math.abs(current_active_val - init_val) < 0.0001 and named_branch_val < init_val then
		minetest.chat_send_player(p_name, "[ValueAPI] PASS: value(player) used 'main'; value(player,'value_api_test') reflected slowdown.")
	else
		minetest.chat_send_player(p_name, "[ValueAPI] FAIL: mismatch. active=" .. current_active_val .. ", named=" .. named_branch_val .. ", init=" .. init_val)
		return
	end

	-- now switch to that branch, confirm speed:value() uses that branch by default
	speed:checkout_branch(player, "value_api_test")
	local active_switched_val = speed:value(player)
	if math.abs(active_switched_val - named_branch_val) < 0.0001 then
		minetest.chat_send_player(p_name, "[ValueAPI] PASS: after checkout, value(player) matches 'value_api_test' branch value.")
	else
		minetest.chat_send_player(p_name, "[ValueAPI] FAIL: after checkout mismatch. got=" .. active_switched_val .. " vs named=" .. named_branch_val)
	end
end

--------------------------------------------------------------------------------
-- /test_monoids runs all tests in sequence
--------------------------------------------------------------------------------

local all_tests = {
	{name = "AddRemove",            func = test_speed_add_remove,        delay = 2},
	{name = "BranchIsolation",      func = test_branch_isolation,        delay = 2},
	{name = "BranchConcurrent",     func = test_branch_concurrent,       delay = 4},
	{name = "OnChangeAll",          func = test_onchange_listen_all,     delay = 2},
	{name = "OnChangeActive",       func = test_onchange_listen_active,  delay = 2},
	{name = "BranchNameCheck",      func = test_branch_name_check,       delay = 1},
	{name = "ActiveBranchGet",      func = test_active_branch_check,     delay = 1},
	{name = "BranchDelete",         func = test_branch_delete_check,     delay = 2},
	{name = "GetBranches",          func = test_get_branches,            delay = 1},
	{name = "OnBranchCreateDelete", func = test_on_branch_create_delete, delay = 2},
	{name = "NewBranchMethod",      func = test_new_branch_method,       delay = 2},
	{name = "MainBranchCantDelete", func = test_main_branch_cant_delete, delay = 1},
	{name = "SpeedJumpTogether",    func = test_speed_and_jump_together, delay = 3},
	{name = "ValueAPI",             func = test_value_api,               delay = 2},
}

local function run_tests_sequentially(player, index)
	local p_name = player:get_player_name()
	if index > #all_tests then
		minetest.chat_send_player(p_name, "All tests completed!")
		return
	end

	local info = all_tests[index]
	minetest.chat_send_player(p_name, "\n>>> " .. index .. "/" .. #all_tests .. " Running: " .. info.name .. "...")
	info.func(player)

	minetest.after(info.delay, function()
		local again = minetest.get_player_by_name(p_name)
		if not again then return end
		run_tests_sequentially(again, index + 1)
	end)
end

minetest.register_chatcommand("test_monoids", {
	description = "Runs ALL monoid tests in sequence.",
	privs = {monoid_master = true},
	func = function(p_name)
		local player = minetest.get_player_by_name(p_name)
		if player then
			minetest.chat_send_player(p_name, "Starting all monoid tests...")
			run_tests_sequentially(player, 1)
		end
	end,
})
