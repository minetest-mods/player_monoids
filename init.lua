-- Copyright (c) raymoo 2016
-- Licensed under Apache 2.0 license. See COPYING for details.

-- Any documentation here are internal details, please avoid using them in your
-- mod.

local modpath = minetest.get_modpath(minetest.get_current_modname())

player_monoids = {}

local mon_meta = {}

mon_meta.__index = mon_meta

-- A monoid object is a table with the following fields:
--   player_map: A map from player names to their effect tables. Effect tables
--     are maps from effect IDs to values.
--   value_cache: A map from player names to the cached value for the monoid.
--   next_id: The next unique ID to assign an effect.

local function monoid(def)
        local mon = {}

	local p_map = {}
        mon.player_map = p_map

        mon.next_id = 1

	local v_cache = {}
	mon.value_cache = v_cache

        setmetatable(mon, mon_methods)

	minetest.register_on_leaveplayer(function(player)
		local p_name = player:get_player_name()
		p_map[p_name] = nil
		v_cache[p_name] = nil
	end)

        return mon
end

player_monoids.make_monoid = monoid

function mon_meta:add_change(player, value)
        local p_name = player:get_player_name()
        
        local p_effects = self.player_map[p_name]
        if p_effects == nil then
                p_effects = {}
                self.player_map[p_name] = p_effects
        end

        local actual_id

        if id then
                actual_id = id
        else
                actual_id = self.next_id
                self.next_id = actual_id + 1
        end

        local old_total = self.value_cache[p_name]
        p_effects[actual_id] = value
	local new_total = self.fold(p_effects)
        self.value_cache[p_name] = new_total
        
        self.apply(new_total, player)
        self.on_change(old_total, new_total, player)
end

function mon_meta:del_change(player, id)
        local p_name = player:get_player_name()

        local p_effects = self.player_map[p_name]
        if p_effects == nil then return end

        local old_total = self.value_cache[p_name]
        p_effects[id] = nil
        local new_total = self.fold(p_effects)
        self.value_cache[p_name] = new_total

        self.apply(new_total, player)
        self.on_change(old_total, new_total, player)
end

function mon_meta:value(player)
        local p_name = player:get_player_name()
        return self.value_cache[p_name] or self.identity
end
