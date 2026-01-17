# Player Monoids Library Documentation

## Introduction

The **Player Monoids Library** is designed to solve the problem of conflicting player state changes in Luanti when multiple mods are involved.
For example, one mod might want to increase a player's speed (`ObjectRef:set_physics_override`), while another mod reduces it. Without a structured way to combine these changes, mods can overwrite each other's effects, leading to unpredictable behavior.

**Undocumented functions or variables may change at any time without notice.**


### Terminology

- **Monoid**: Represents one aspect of the player state
    - Examples: movement speed factor, corruption level, reputation level, the `fast` privilege,
      environmental effects
- **Branch**: A situation or time-based context of the player.
    - Monoids of the active branch are applied to the player. This allows context-based overriding.
    - Use-cases: freezing the player (sleeping in bed), increased armor groups in PvP,
      increased jump height while playing a minigame.


## Monoids

Monoids can be categorized based on how they combine values:

- **Multiplicative**: Combine values using multiplication (e.g., speed multipliers).
- **Additive**: Combine values using addition (e.g., armor bonuses).
- **Custom Logic**: Use custom logic to combine values (e.g., vectors for directional effects).


### Built-in monoids

[standard_monoids.lua](standard_monoids.lua) provides the following *monoids*:

- Player physics overrides: (multipliers)
     - `player_monoids.speed`: movement speed
     - `player_monoids.jump`: jump speed
     - `player_monoids.gravity`: acceleration.
- Privilege management (*OR*-combined): `fly`, `noclip`
- Player appearance: (multipliers)
    - `player_monoids.collisionbox`: Scales the player’s collision box with component-wise multiplication.
    - `player_monoids.visual_size`: Scales the player’s visual size as a 2D multiplier vector.


### Monoid Definition

A *monoid* is defined as a Lua table. See also: `player_monoids.make_monoid`.
You may find an example below.

```lua
{
	identity = value,                   -- Neutral/default value
	combine = function(value1, value2), -- Combines two values
	fold = function({values, ...}),     -- Combines multiple elements
	apply = function(value, player),    -- Applies the combined value to the player
	on_change = function(old_value, new_value, player, branch_name),  -- Optional callback for value changes
	listen_to_all_changes = boolean     -- Optional; enables callbacks across branches
}
```

- `identity`
    - This is the base onto which all values of the active monoids are applied to
    . As a rule of thumb:
        - If `combine` is multiplicative: `identity = 1.0`
        - If `combine` is additive: `identity = 0`
- `combine = function(value1, value2)`
    - Combines two values, originating from separate `monoid:add_change`.
    - Return value: output value (same type as `value1` and `value2`)
    - This function *must* be associative. Hence these two expressions must be equal:
        - `combine(a, combine(b, c))`
        - `combine(combine(a, b), c)`
- `fold = function({ value1, value2, ... })`
    - Identical logic as in `combine`, but accepting more values.
- `apply = function(value, player)`
    - `player` (ObjectRef): Target to apply the `value`
    - Example: `player:set_physics_override({ speed = value })`
- `on_change = function(old_value, new_value, player, branch)`
    - Optional. This callback is run after a new value was evaluated.
    - `branch` (table): This is equal to `monoid:get_active_branch(player)`.
- `listen_to_all_changes = boolean`
    - When set to `true`, `on_change` will be called on *every change*, even if `branch` is not the currently active branch.
    - Default: `false`.
- `on_branch_created(monoid, player, branch_name)`
    - Optional. Called when a new branch is created.
- `on_branch_deleted(monoid, player, branch_name)`
    - Optional. Called when a branch is deleted.

**Types of the parameters above:**

- `branch_name`: a `string`. e.g. `"main"` (default branch)
- `monoid`: see [Monoid Definition]
- `player`: an `ObjectRef` instance


#### Example

In order to overwrite the `speed` physics override (a built-in monoid), the following
definition could be used:

```lua
{
	identity = 1,
	combine = function(a, b)
		-- Scale linearly, based on the default 1.
		return a * b
	end,
	fold = function(t)
		-- Same as `combine` but for more elements
		local result = 1
		for _, v in pairs(t) do
			result = result * v
		end
		return result
	end,
	apply = function(multiplier, player)
		player:set_physics_override({speed = multiplier})
	end,
	on_change = function(old_val, new_val, player, branch)
		local branch_name = branch:get_name()
		core.log("Speed changed from " .. old_val .. " to " .. new_val .. " on branch " .. branch_name)
	end
```


## Branches

Branches allow mods to isolate state changes into separate contexts without interfering with each other. Each branch maintains its own set of modifiers and can be activated independently.
For each player exactly one branch is active at a time.

- Default branch: `"main"`
- Default values: as given by `monoid.identity`

**Branch management and assignemnt:**

- New branch: `monoid:new_branch(player, name)`
- Switch to branch: `monoid:checkout_branch(player, name)`
- Get branch: `monoid:get_branch(name)`

The inactive branches can still be modified in the background, but their combined values won't affect the player's state until they get activated.


## API Reference

*Optional arguments are denoted with `[, arg1]`.

Notes:

- `branch_name`: a `string`
- `id`: a `number` or a unique mod-defined `string` to identify the change, e.g. `my_boots_mod:speedy_boots`.
- `monoid`: see [Monoid Definition]
- `player`: an `ObjectRef` instance


### Monoid API

- `player_monoids.make_monoid(monoid_def)`
    - Initializes and returns a new monoid based on `monoid_def`.
    - `monoid_def` (table): see [Monoid Definition]
- `monoid:add_change(player, value[, id, branch_name])`
    - Applies a change represented by `value` to the player.
    - If the change `id` already exists in the branch, it will be overwritten.
    - If no `branch_name` is provided, `"main"` will be used.
    - Returns `id` or a generated unique ID of the change.
- `monoid:del_change(player, id[, branch_name])`
    - Removes the change represented by `id` from the player.
    - If no `branch_name` is provided, `"main"` will be used.
- `monoid:value(player[, branch_name])`
    - Gets the value of this monoid for the specified player and branch.
    - If no `branch_name` is provided, the **active branch** will be used.
    - Returns the combined value for this monoid.


### Branch API

-  `monoid:new_branch(player, branch_name)`
    - Creates a new branch for a player, but does not switch to it.
    - Returns a [Branch Handler] object.
- `mononid:checkout_branch(player, branch_name)`
    - Switches the player's active branch to the specified one, creating it if it doesn't exist.
    - The player's state is immediately updated to reflect the combined value of the new active branch.
    - Returns a [Branch Handler] object.
- `monoid:get_active_branch(player)`
    - Gets a [Branch Handler] object representing the player's currently active branch.
- `monoid:get_branch(branch_name)`
    - Retrieves a handler object for the specified branch.
    - Returns `false` if the branch does not exist.
- `monoid:get_branches(player)`
    - Returns a table:
        - Key: string, branch name
        - Value: [Branch Handler] object
- `monoid:reset_branch(player[, branch_name])`
    - Clears all changes associated with a player's branch.
    - If no branch name is provided, `"main"` will be used.


#### Branch Handler

The branch handler (table) provides methods for managing changes specific to the branch.

**Functions:**

- `branch:get_name()`
    - Retrieves this branch’s name as a string.
- `branch:add_change(player, value[, id])`:
    - Adds a change to this branch.
    - Wrapper for `monoid:add_change`
- `branch:del_change(player, id)`
    - Removes a change from this branch by its ID.
    - Wrapper for `monoid:del_change`
- `branch:value(player)`
    - Evaluates and returns this branch’s current combined value for a specific player.
    - Wrapper for `monoid:value`
- `branch:reset(player)`
    - Discards all changes (`id` + `value`) belonging to this branch and player.
- `branch:delete(player)`
    - Deletes this branch for the specified player.
    - If the deleted branch is the active branch, the active branch will be switched to `"main"`.
    - The `"main"` branch cannot be deleted.
