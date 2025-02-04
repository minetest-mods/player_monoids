# Player Monoids Library Documentation



## Table of Contents
1. [Introduction](#introduction)
   - 1.1 [Use Cases and Types](#use-cases-and-types)
   - 1.2 [Definition Structure](#definition-structure)
2. [Branch System](#branch-system)
3. [API Reference](#api-reference)



## Introduction

The **Player Monoids Library** is designed to solve the problem of conflicting player state changes in Luanti when multiple mods are involved. For example, one mod might want to increase a player's speed, while another mod reduces it. Without a structured way to combine these changes, mods can overwrite each other's effects, leading to unpredictable behavior.

This library introduces **monoids**, which represent specific aspects of the player state, such as speed modifiers, jump height, or even custom states like corruption levels or reputation systems. Monoids allow changes from multiple mods to be combined consistently and predictably. Additionally, the library supports **branches**, which isolate changes into separate contexts. This makes it possible to maintain different states for different scenarios, such as minigames or alternate dimensions.

### Use Cases and Types

Monoids are useful for managing both built-in player attributes and custom mod-defined states. For example:

- **Built-in Attributes**: Monoids can manage physics overrides like speed multipliers, jump height modifiers, or gravity changes. They can also handle privilege management (e.g., enabling or disabling fly or noclip combining booleans with the *or* operator) or armor values.
- **Custom Mod States**: Mods can define their own monoids for features like corruption levels, reputation systems, or environmental effects. For instance, you could create a monoid that tracks "lucky directions" as vectors.

Monoids can be categorized based on how they combine values:
- **Multiplicative Monoids**: Combine values using multiplication (e.g., speed multipliers).
- **Additive Monoids**: Combine values using addition (e.g., armor bonuses).
- **Custom Logic Monoids**: Use custom logic to combine values (e.g., vectors for directional effects).

---

### Definition Structure

A monoid is defined as a Lua table that specifies how values are combined, applied to the player, and managed. The structure includes the following fields:

```lua
{
  combine = function(elem1, elem2),  -- Combines two elements (must be associative)
  fold = function({elems}),          -- Combines multiple elements
  identity = value,                  -- Neutral/default value
  apply = function(value, player),   -- Applies the combined value to the player
  on_change = function(old, new, player, branch),  -- Optional callback for value changes
  listen_to_all_changes = boolean    -- Optional; enables branch-wide callbacks
}
```

Each field plays a specific role in defining the behavior of the monoid:

- **`combine`** defines how two values are merged. The function must be associative, meaning that `combine(a, combine(b, c))` should be equivalent to `combine(combine(a, b), c)`. For example, in a speed multiplier monoid:

```lua
  combine = function(a, b) return a * b end
```

- **`fold`** combines multiple values at once by applying `combine` iteratively. It processes a table of values and merges them into one:
  
```lua
fold = function(t)
 local result = 1
 for _, v in pairs(t) do result = result * v end
 return result
end
```

- **`identity`** is the neutral default value that will be used when there are no status effects active for a particular monoid. When combined with any other value, it leaves it unchanged. For example:
   - Speed multipliers: `identity = 1.0`
   - Additive bonuses: `identity = 0`

- **`apply`** translates the combined monoid value into actual effects on the player's state:
  
```lua
apply = function(multiplier, player)
 player:set_physics_override({speed = multiplier})
end
```

- **`on_change`** is an optional callback triggered whenever the monoid's value changes for a player:
  
```lua
on_change = function(old_val, new_val, player, branch)
 local branch_name = branch:get_name()
 core.log("Speed changed from " .. old_val .. " to " .. new_val .. " on branch " .. branch_name)
end
```

- **`listen_to_all_changes`**, when set to `true`, ensures that `on_change` is triggered for all branch updates instead of just the active branch.

- **`on_branch_created(monoid, player, branch_name)`**: Optional callback, called when a new branch is created.

- **`on_branch_deleted(monoid, player, branch_name)`**: Optional callback, called when a branch is deleted.

---



## Branch System

Branches allow mods to isolate state changes into separate contexts without interfering with each other. Each branch maintains its own set of modifiers and can be activated independently.

By default, every player starts on the `"main"` branch. This branch represents their normal state and is created automatically when a monoid is initialized. Additional branches can be created and accessed in three ways:
- Using `monoid:new_branch(player, name)` to create a new branch without activating it
- Using `monoid:checkout_branch(player, name)` to switch the player's active branch, creating it if needed
- Using `monoid:get_branch(name)` to get a wrapper for managing the branch at any time, or false if it doesn't exist

When switching branches with `checkout_branch`, the player's state is immediately updated to reflect the combined value of the new active branch.

The inactive branches can still be modified in the background, but their combined values won't affect the player's state until they get activated.

---



## API Reference
#### `player_monoids.make_monoid(monoid_def)`
The `monoid` object mentioned in this API's methods has to first be created using this function. `monoid_def` is a table defining the monoid’s behavior (see [Definition Structure](#definition-structure)).

---

#### `monoid:add_change(player, value[, id, branch_name])`
Applies a change represented by `value` to the player. Takes a `player` object, a `value` parameter that must be valid for this monoid, an optional *branch-unique* string `id` (if not provided, a random one will be generated), and an optional `branch_name` parameter (if not provided, the `"main"` branch will be used). Returns the ID of the added change.

---

#### `monoid:del_change(player, id[, branch_name])`
Removes the change represented by `id` from the player. If `branch_name` is not provided, the `"main"` branch will be used.

---

#### `monoid:value(player[, branch_name])`
Gets the value of this monoid for a specific player and branch. Takes a player object and an optional `branch_name` parameter. If `branch_name` is not provided, the **active branch** will be used. Returns the combined value for this monoid.

---

#### `monoid:new_branch(player, branch_name)`
Creates a new branch for a player, but does not switch to it. Returns the handler object for the new branch.
- The returned handler provides methods for managing changes specific to that branch:
   - **`add_change(player, value[, id])`**: adds a change to this specific branch.
   - **`del_change(player, id)`**: removes a change from this specific branch by its ID.
   - **`value(player)`**: gets this branch’s current combined value for a specific player.
   - **`get_name()`**: retrieves this branch’s name as a string.
   - **`reset(player)`**: clears all changes on this branch for the specified player.
   - **`delete(player)`**: deletes this branch for the specified player. If the deleted branch is the active branch, the active branch will be switched to `"main"`. You can't delete the main branch.

---

#### `mononid:checkout_branch(player, name)`
Switches the player's active branch to the specified one, creating it if it doesn't exist. Returns the handler object for the new branch.

---

#### `monoid:get_active_branch(player)`
Gets a handler object representing the player's currently active branch.

---

#### `monoid:get_branch(name)`
Retrieves a handler object for the specified branch. Returns `false` if the branch does not exist.

---

#### `monoid:get_branches(player)`
Returns a table of branch wrappers, keyed by branch name, for all branches associated with the player.

---

#### `monoid:reset_branch(player[, branch_name])`
Clears all changes associated with a player's branch. If no branch name is provided, it resets `"main"` by default.
