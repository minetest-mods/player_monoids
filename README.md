# Player Monoids Library

This is a small library for managing global player state in Luanti, ensuring that multiple mods can modify player attributes without conflicts. The README provides an overview of the mod's purpose and functionality. For a detailed breakdown of available functions and usage, refer to **API.md**.

This mod introduces **monoids**, which represent specific aspects of player state, such as speed modifiers, jump height, or even custom attributes like corruption levels or reputation systems. Monoids allow multiple mods to apply effects in a structured manner, preventing unintended overrides.

Additionally, the mod now includes **branches**, which allow different states to exist independently. This is useful for features like minigames, temporary effects, or alternate player states that should not interfere with the main game.

## Global Player State

Player state consists of various properties such as physics overrides, privileges, and other custom attributes. These properties are often modified by different mods, leading to unintended side effects. For example, a mod that grants a temporary speed boost might be overridden when another mod resets the player’s movement speed, inadvertently removing the boost.

For example, a player could be under a speed boost effect from a `playereffects` mod and then sleep in a bed. If the bed mod resets the player’s speed, it might remove the boost entirely. Without a structured approach, the interaction between these mods can be unpredictable, potentially leading to exploits such as permanent speed boosts.

Player Monoids prevents this issue by allowing changes to be layered and combined correctly using monoids and branch-based state management.

## Monoids

### Creation

A monoid in Player Monoids is an abstraction over a specific piece of player state. Examples include physics overrides (like speed and gravity), privilege toggles (fly, noclip), and custom attributes (e.g., status effects, corruption levels). You define a monoid like this:

```lua
-- The values in my speed monoid must be speed multipliers (numbers).
mymod.speed_monoid = player_monoids.make_monoid({
	combine = function(speed1, speed2)
		return speed1 * speed2
	end,
	fold = function(tab)
		local res = 1
		for _, speed in pairs(tab) do
			res = res * speed
		end
		return res
	end,
	identity = 1,
	apply = function(speed, player)
		player:set_physics_override({ speed = speed })
	end,
	on_change = function() return end,
})
```

This defines how speed multipliers combine, the identity value (`1`, meaning no change), and how the monoid applies its effects to the player.

### Use

You modify player state using the `add_change` and `del_change` methods:

```lua
-- Increase player speed temporarily
local zoom_id = mymod.speed_monoid:add_change(some_player, 2)
minetest.after(5, function() mymod.speed_monoid:del_change(some_player, zoom_id) end)
```

You can also specify a custom string identifier:

```lua
-- Speed boost with named identifier
mymod.speed_monoid:add_change(some_player, 2, "mymod:zoom")
minetest.after(5, function() mymod.speed_monoid:del_change(some_player, "mymod:zoom") end)
```

### Reading Values

You can use `monoid:value(player)` to read the current value of the monoid for that player. This is useful when the monoid represents a derived attribute rather than a direct player state value.

### Branch System

Branches allow state changes to be contained within separate contexts, preventing interference between unrelated modifications. Every player starts in the `"main"` branch, but additional branches can be created and managed separately.

For example:

```lua
local speed_branch = mymod.speed_monoid:new_branch(some_player, "minigame")
speed_branch:add_change(some_player, 2)
```

When switching branches, the new branch’s state is immediately applied, while the previous one is preserved but inactive:

```lua
mymod.speed_monoid:checkout_branch(some_player, "minigame")
```

To return to the normal game state:

```lua
mymod.speed_monoid:checkout_branch(some_player, "main")
```

### Nesting Monoids

You may have already noticed one limitation of this design. That is, for each kind of player state, you can only combine state changes in one way. If the standard speed monoid combines speed multipliers by multiplication, you cannot change it to instead choose the highest speed multiplier. Unfortunately, there is currently no way to change this - you will have to hope that the given monoid combines in a useful way. However, it is possible to manage a subset of the values in a custom way.

If you want to manage subsets of a monoid's values separately, you can create a nested monoid that modifies only a portion of the state while keeping compatibility with the parent monoid.

Suppose that a speed monoid (`mymod.speed_monoid`) already exists, using multiplication, but you want to write a mod with speed boosts, and only apply the strongest boost. Most of it could be done the same way:

```lua
-- My speed boosts monoid takes speed multipliers (numbers) that are at least 1.
newmod.speed_boosts = player_monoids.make_monoid({
    combine = function(speed1, speed2)
        return math.max(speed1, speed2)
    end,
    fold = function(tab)
        local res = 1
        for _, speed in pairs(tab) do
            res = math.max(res, speed)
        end
        return res
    end,
    identity = 1,
    apply = function(speed, player)
        mymod.speed_monoid:add_change(player, speed, "newmod:speed_boosts")
    end,
    on_change = function() return end,
})
```

This means the speed boosts we control can be limited to the strongest boost, but the resulting boost will still play nice with speed effects from other mods.

You could even add another "nested monoid" just for speed maluses, that takes the worst speed drain and applies it as a multiplier.

However, we cannot just change the player speed directly in `apply`, otherwise we will break compatibility with the original speed monoid! The trick here is to use the original monoid as a proxy for our effects.

```lua
apply = function(speed, player)
    mymod.speed_monoid:add_change(player, speed, "newmod:speed_boosts")
end
```

This ensures that our boost calculation stays separate while still being compatible with other modifications. You could also introduce another nested monoid for handling slow effects, ensuring only the most significant reduction takes effect.&#x20;

## Predefined monoids

### Physics Overrides

These monoids modify physics properties using multipliers:

- `player_monoids.speed`
- `player_monoids.jump`
- `player_monoids.gravity`

### Privileges

These monoids toggle player privileges, using boolean logic:

- `player_monoids.fly`
- `player_monoids.noclip`

### Other

- `player_monoids.collisionbox` - Adjusts the player’s collision box with component-wise multiplication.
- `player_monoids.visual_size` - Modifies the player’s visual size as a 2D multiplier vector.

## Caveats

- If the global state managed by a monoid is modified by something other than the monoid, you will have the same problem as when two mods both independently try to modify global state without going through a monoid.
- This includes `playereffects` effects that affect global player state without going through a monoid.
- You will also get problems if you use multiple monoids to manage the same global state.
- The order that different effects get combined together is based on key order, which may not be predictable. So you should try to make your monoids commutative in addition to associative, or at least not care if the order of two changes is swapped.
- Mods should account for the fact that the active branch may change at any time - they should not assume that their effects will always be applied to the player.
- If a mod wants to make sure to always be working with the main branch values, it should be doing that through the optional branch_name parameter in the monoid functions (such as `monoid:value(player, "main")`, and/or by implementing branch checks in `on_change()`).

---

For more details, including function signatures and advanced usage, refer to **API.md**.