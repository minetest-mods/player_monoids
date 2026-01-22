local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"

local function copy_value(v)
	return type(v) == "table" and table.copy(v) or v
end

player_monoids = {
	api_version = 2
}

local mon_meta = {}
mon_meta.__index = mon_meta

local nop = function() end

-- A monoid object is a table with the following fields:
--   def: The monoid definition.
--   player_map: A map from player names to their branch maps. Branch maps
--     contain branches, and each branch holds an 'effects' table.
--   next_id: The next unique ID to assign an effect.

player_monoids.make_monoid = function(def)
	assert(type(def) == "table")

	-- Clone the definition to avoid mutating the original
	local actual_def = {
		-- Default values of optional fields
		apply = nop,
		on_change = nop,
		on_branch_created = nop,
		on_branch_deleted = nop,
		listen_to_all_changes = false,
	}
	for k, v in pairs(def) do
		actual_def[k] = v
	end

	-- Mandatory fields
	assert(actual_def.identity ~= nil)
	-- (combine is unused)
	assert(type(actual_def.fold) == "function")
	assert(type(actual_def.apply) == "function")

	-- Optional fields
	assert(type(actual_def.on_change) == "function")
	assert(type(actual_def.listen_to_all_changes) == "boolean")
	assert(type(actual_def.on_branch_created) == "function")
	assert(type(actual_def.on_branch_deleted) == "function")

	local mon = {}
	mon.def = actual_def
	mon.player_map = {} -- Contains the branch data
	mon.next_id = 1

	setmetatable(mon, mon_meta)

	-- Clear out data when player leaves
	minetest.register_on_leaveplayer(function(player)
		local p_name = player:get_player_name()
		mon.player_map[p_name] = nil
	end)

	return mon
end


--- @brief Gets or initializes the player data of the current monoid
--- @param p_name     string
--- @param do_reset   boolean, whether to reset all player data. Default: false
--- @return A table, the player data.
function mon_meta:_get_player_data(p_name, do_reset)
	local p_data
	if not do_reset then
		p_data = self.player_map[p_name]
		if p_data then
			return p_data
		end
	end

	p_data = {
		active_branch = "main",
		branches = {}
	}
	self.player_map[p_name] = p_data

	-- Create the main branch
	local bdata = self:_get_branch_data(p_name, "main")
	p_data.last_value = bdata.value -- for 'on_change'

	return p_data
end

--- @brief Gets or initializes the givne branch
function mon_meta:_get_branch_data(p_name, branch_name)
	local branches = self.player_map[p_name].branches
	local branch = branches[branch_name]
	if branch then
		return branch
	end

	-- Create
	branch = {
		effects = {},
		value = copy_value(self.def.identity)
	}
	branches[branch_name] = branch

	if branch_name ~= "main" then
		local player = core.get_player_by_name(p_name)
		if player then
			self.def.on_branch_created(self, player, branch_name)
		end
	end
	return branch
end

-- decide if to call on_change for this change based on listen_to_all_changes
function mon_meta:call_on_change(old_value, new_value, player, branch_name)
	local p_name = player:get_player_name()
	if self.def.listen_to_all_changes or (self.player_map[p_name].active_branch == branch_name) then
		self.def.on_change(old_value, new_value, player, self:get_branch(branch_name))
	end
end

--- @brief Internal function to change (or remove) an effect
--- @param player       ObjectRef
--- @param value        new effect value (may be nil)
--- @param id           string/integer, effect ID
--- @param branch_name  string, branch to modify
function mon_meta:_set_change(player, value, id, branch_name)
	assert(value == nil or type(value) == type(self.def.identity))

	local p_name = player:get_player_name()
	-- TODO: 'new_branch' and 'checkout_branch' should be used instead to create the branch!
	local p_branch_data = self:_get_branch_data(p_name, branch_name)

	local old_total = p_branch_data.value

	p_branch_data.effects[id] = value
	local new_total = self.def.fold(p_branch_data.effects)
	p_branch_data.value = new_total

	if self.player_map[p_name].active_branch == branch_name then
		self.def.apply(new_total, player)
	end

	self:call_on_change(old_total, new_total, player, branch_name)
end

function mon_meta:add_change(player, value, id, branch_name)
	local p_name = player:get_player_name()
	branch_name = branch_name or "main"

	-- Create if not existing
	self:_get_player_data(p_name)
	self:_get_branch_data(p_name, branch_name)

	if not id then
		id = self.next_id
		self.next_id = self.next_id + 1
	end

	self:_set_change(player, value, id, branch_name)
	return id
end

function mon_meta:del_change(player, id, branch_name)
	local p_name = player:get_player_name()
	local p_data = self:_get_player_data(p_name)

	branch_name = branch_name or "main"
	local p_branch_data = p_data.branches[branch_name]
	if not p_branch_data then
		return
	end

	self:_set_change(player, nil, id, branch_name)
end

function mon_meta:reset_branch(player, branch_name)
	local p_name = player:get_player_name()
	local p_data = self:_get_player_data(p_name)

	branch_name = branch_name or "main"
	local bdata = p_data.branches[branch_name]
	if not bdata then
		return -- Branch doesn't exist, nothing to reset
	end

	local old_total = bdata.value

	-- Clear effects and recalc
	bdata.effects = {}
	local new_total = copy_value(self.identity)
	bdata.value = new_total

	local active_branch = p_data.active_branch or "main"
	if branch_name == active_branch then
		-- Apply the new values
		p_data.last_value = bdata.value
		self.def.apply(bdata.value, player)
	end

	-- Fire on_change for the branch being reset
	self:call_on_change(old_total, new_total, player, branch_name)
end

-- Create a branch for a player, but do NOT check it out
function mon_meta:new_branch(player, branch_name)
	local p_name = player:get_player_name()

	-- Create if not existing
	self:_get_player_data(p_name)
	self:_get_branch_data(p_name, branch_name)

	return self:get_branch(branch_name)
end

function mon_meta:get_branch(branch_name)
	if not branch_name then
		return false
	end

	local monoid = self
	return {
		add_change = function(_, player, value, id)
			return monoid:add_change(player, value, id, branch_name)
		end,
		del_change = function(_, player, id)
			return monoid:del_change(player, id, branch_name)
		end,
		value = function(_, player)
			return monoid:value(player, branch_name)
		end,
		reset = function(_, player)
			return monoid:reset_branch(player, branch_name)
		end,
		get_name = function(_)
			return branch_name
		end,
		delete = function(_, player)
			return monoid:delete_branch(player, branch_name)
		end,
	}
end

function mon_meta:get_active_branch(player)
	local p_name = player:get_player_name()
	local active = self.player_map[p_name] and self.player_map[p_name].active_branch or "main"
	return self:get_branch(active)
end

function mon_meta:get_branches(player)
	local p_name = player:get_player_name()
	local p_data = self:_get_player_data(p_name)

	local result = {}
	for b_name, _ in pairs(p_data.branches) do
		result[b_name] = self:get_branch(b_name)
	end
	return result
end

function mon_meta:delete_branch(player, branch_name)
	local p_name = player:get_player_name()
	local player_data = self:_get_player_data(p_name)

	local existing_branch = player_data.branches[branch_name]
	if not existing_branch or branch_name == "main" then
		return false
	end

	-- If it's the active branch, switch to main
	if player_data.active_branch == branch_name then
		player_data.active_branch = "main"
		local new_main_total = self:value(player, "main")

		player_data.last_value = new_main_total
		self.def.apply(new_main_total, player)
	end

	-- Remove the branch
	player_data.branches[branch_name] = nil

	self.def.on_branch_deleted(self, player, branch_name)
	return true
end

minetest.register_on_joinplayer(function(player)
	local p_name = player:get_player_name()
	for _, monoid in pairs(player_monoids) do
		if type(monoid) == "table" and monoid._get_player_data then
			monoid:_get_player_data(p_name)
		end
	end
end)

function mon_meta:value(player, branch_name)
	local p_name = player:get_player_name()
	local p_data = self:_get_player_data(p_name)

	branch_name = branch_name or p_data.active_branch
	local bdata = p_data.branches[branch_name]
	return bdata and bdata.value or copy_value(self.def.identity)
end

function mon_meta:checkout_branch(player, branch_name)
	local p_name = player:get_player_name()
	local p_data = self:_get_player_data(p_name)

	local old_total = p_data.last_value
	local checkout_branch = self:new_branch(player, branch_name)

	p_data.active_branch = branch_name
	local new_total = self:value(player)

	p_data.last_value = new_total
	self.def.apply(new_total, player)
	self:call_on_change(old_total, new_total, player, branch_name)

	return checkout_branch
end

-- Finally, load the additional files

dofile(modpath .. "standard_monoids.lua")
dofile(modpath .. "test.lua")
