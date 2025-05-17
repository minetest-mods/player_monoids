local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"

player_monoids = {}

local mon_meta = {}
mon_meta.__index = mon_meta

local nop = function() end

-- A monoid object is a table with the following fields:
--   def: The monoid definition.
--   player_map: A map from player names to their branch maps. Branch maps
--     contain branches, and each branch holds an 'effects' table.
--   value_cache: A map from player names to the cached value for the monoid.
--   next_id: The next unique ID to assign an effect.

--[[
In def, you can optionally define:

  - apply(new_value, player)
  - on_change(old_value, new_value, player, branch)
  - listen_to_all_changes (bool)
  - on_branch_created(monoid, player, branch_name)
  - on_branch_deleted(monoid, player, branch_name)

These hooks allow you to respond to monoid changes, branch creation, and branch deletion.
]]

local function monoid(def)
	local mon = {}

	-- Clone the definition to avoid mutating the original
	local actual_def = {}
	for k, v in pairs(def) do
		actual_def[k] = v
	end

	if not actual_def.apply then
		actual_def.apply = nop
	end
	if not actual_def.on_change then
		actual_def.on_change = nop
	end
	if not actual_def.on_branch_created then
		actual_def.on_branch_created = nop
	end
	if not actual_def.on_branch_deleted then
		actual_def.on_branch_deleted = nop
	end
	if actual_def.listen_to_all_changes == nil then
		actual_def.listen_to_all_changes = false
	end

	mon.def = actual_def

	mon.player_map = {} -- p_name -> { active_branch="main", branches={ branch_name={ effects={}, value=...} } }
	mon.value_cache = {} -- p_name -> numeric or table
	mon.next_id = 1

	setmetatable(mon, mon_meta)

	-- Clear out data when player leaves
	minetest.register_on_leaveplayer(function(player)
		local p_name = player:get_player_name()
		mon.player_map[p_name] = nil
		mon.value_cache[p_name] = nil
	end)

	-- Initialize branches for the monoid
	function mon:init_branches(player_name)
		self.player_map[player_name] = {
			active_branch = "main",
			branches = {
				main = {
					effects = {},
					value = def.identity
				}
			}
		}
	end

	return mon
end

player_monoids.make_monoid = monoid

local function init_player_branches_if_missing(self, p_name)
	if not self.player_map[p_name] then
		self:init_branches(p_name)
	end
end

-- Create or return existing branch. If a new one is created, fire on_branch_created.
local function get_or_create_branch_data(self, p_name, branch_name)
	local branches = self.player_map[p_name].branches
	local existing_branch = branches[branch_name]

	if not existing_branch then
		branches[branch_name] = {
			effects = {},
			value = self.def.identity
		}

		existing_branch = branches[branch_name]

		local player = minetest.get_player_by_name(p_name)
		if player then
			self.def.on_branch_created(self, player, branch_name)
		end
	end

	return existing_branch
end

-- decide if to call on_change for this change based on listen_to_all_changes
function mon_meta:call_on_change(old_value, new_value, player, branch_name)
	local p_name = player:get_player_name()
	if self.def.listen_to_all_changes or (self.player_map[p_name].active_branch == branch_name) then
		self.def.on_change(old_value, new_value, player, self:get_branch(branch_name))
	end
end

function mon_meta:add_change(player, value, id, branch_name)
	local p_name = player:get_player_name()
	init_player_branches_if_missing(self, p_name)

	local branch = branch_name or "main"
	local p_branch_data = get_or_create_branch_data(self, p_name, branch)

	local p_effects = p_branch_data.effects

	local actual_id = id or self.next_id
	if not id then
		self.next_id = actual_id + 1
	end

	local old_total = p_branch_data.value
	p_effects[actual_id] = value

	local new_total = self.def.fold(p_effects)
	p_branch_data.value = new_total

	if self.player_map[p_name].active_branch == branch then
		self.def.apply(new_total, player)
	end

	self:call_on_change(old_total, new_total, player, branch)
	return actual_id
end

function mon_meta:del_change(player, id, branch_name)
	local p_name = player:get_player_name()
	init_player_branches_if_missing(self, p_name)

	local branch = branch_name or "main"
	local p_branch_data = get_or_create_branch_data(self, p_name, branch)
	if not p_branch_data then return end

	local p_effects = p_branch_data.effects
	local old_total = p_branch_data.value

	p_effects[id] = nil
	local new_total = self.def.fold(p_effects)
	p_branch_data.value = new_total

	if self.player_map[p_name].active_branch == branch then
		self.def.apply(new_total, player)
	end

	self:call_on_change(old_total, new_total, player, branch)
end

function mon_meta:reset_branch(player, branch_name)
	local p_name = player:get_player_name()
	init_player_branches_if_missing(self, p_name)

	local branch = branch_name or "main"
	local bdata = self.player_map[p_name].branches[branch]
	if not bdata then
		return -- Branch doesn't exist, nothing to reset
	end

	local old_total = bdata.value

	-- Clear effects and recalc
	bdata.effects = {}
	local new_total = self.def.fold({})
	bdata.value = new_total

	-- Update active branch
	local active_branch = self.player_map[p_name].active_branch or "main"
	local active_branch_data = self.player_map[p_name].branches[active_branch]

	local active_branch = self.player_map[p_name].active_branch or "main"
	local active_branch_data = self.player_map[p_name].branches[active_branch]
	self.value_cache[p_name] = active_branch_data.value
	self.def.apply(active_branch_data.value, player)

	-- Fire on_change for the branch being reset
	self:call_on_change(old_total, new_total, player, branch)
end

-- new method: create a branch for a player, but do NOT check it out
function mon_meta:new_branch(player, branch_name)
	local p_name = player:get_player_name()
	init_player_branches_if_missing(self, p_name)

	get_or_create_branch_data(self, p_name, branch_name)

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
			local p_name = player:get_player_name()
			init_player_branches_if_missing(monoid, p_name)

			local player_data = monoid.player_map[p_name]
			if not player_data then
				return
			end

			local existing_branch = player_data.branches[branch_name]
			if not existing_branch or branch_name == "main" then
				return
			end

			-- If it's the active branch, switch to main
			if player_data.active_branch == branch_name then
				player_data.active_branch = "main"
				local new_main_total = monoid:value(player, "main")
				monoid.value_cache[p_name] = new_main_total

				monoid.def.apply(new_main_total, player)
			end

			-- Remove the branch
			player_data.branches[branch_name] = nil

			monoid.def.on_branch_deleted(monoid, player, branch_name)
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
	init_player_branches_if_missing(self, p_name)

	local branch_map = self.player_map[p_name].branches or {}
	local result = {}
	for b_name, _ in pairs(branch_map) do
		result[b_name] = self:get_branch(b_name)
	end
	return result
end

function mon_meta:delete_branch(player, branch_name)
	local b = self:get_branch(branch_name)

	if not b then
		return false
	end

	b:delete(player)
end

minetest.register_on_joinplayer(function(player)
	for _, monoid_instance in pairs(player_monoids) do
		if type(monoid_instance) == "table" and monoid_instance.init_branches then
			monoid_instance:init_branches(player:get_player_name())
		end
	end
end)

function mon_meta:value(player, branch_name)
	local p_name = player:get_player_name()
	init_player_branches_if_missing(self, p_name)

	local chosen_branch = branch_name or self.player_map[p_name].active_branch or "main"
	local p_data = self.player_map[p_name]
	local bdata = p_data.branches[chosen_branch]
	if not bdata then
		return self.def.identity
	end

	local calculated_value = self.def.fold(bdata.effects)
	return calculated_value
end

function mon_meta:checkout_branch(player, branch_name)
	local p_name = player:get_player_name()
	init_player_branches_if_missing(self, p_name)

	local old_total = self.value_cache[p_name] or self.def.identity
	local checkout_branch = self:new_branch(player, branch_name)

	self.player_map[p_name].active_branch = branch_name
	local new_total = self:value(player)
	self.value_cache[p_name] = new_total

	self:call_on_change(old_total, new_total, player, branch_name)
	self.def.apply(new_total, player)

	return checkout_branch
end

-- Finally, load the additional files

dofile(modpath .. "standard_monoids.lua")
dofile(modpath .. "test.lua")
