-- Camoflesh_Client.lua
-- Build 42, Single Player
--
-- Mechanic: While the player is carrying a zombie corpse, any zombie that
-- had NOT already spotted the player will ignore them. Zombies that were
-- already targeting the player at the moment the corpse was picked up
-- ("committed" zombies) keep chasing as normal.

-- Keywords used to identify a corpse InventoryItem by its internal type name.
-- PZ Build 42 uses "Corpse" in the type name for picked-up bodies.
local CORPSE_KEYWORDS = { "corpse", "body", "deadbody" }

-- Zombies that were already targeting the player when the corpse was picked up.
-- Stored as {[IsoZombie] = true}. Cleared when the corpse is dropped.
local committedZombies = {}

-- Whether the player was carrying a corpse on the previous tick.
local wasCarryingCorpse = false

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Returns true if an InventoryItem's type name matches a known corpse keyword.
local function isCorpseItem(item)
    local typeName = item:getType()
    if not typeName then return false end
    typeName = string.lower(typeName)
    for _, kw in ipairs(CORPSE_KEYWORDS) do
        if string.find(typeName, kw, 1, true) then
            return true
        end
    end
    return false
end

-- Returns the first corpse InventoryItem in the player's inventory, or nil.
local function findCorpse(player)
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isCorpseItem(item) then
            return item
        end
    end
    return nil
end

-- ── Core logic ────────────────────────────────────────────────────────────────

-- Snapshot every zombie that is currently targeting the player into the
-- committedZombies table. Called once at the moment of corpse pickup.
local function recordCommittedZombies(player)
    committedZombies = {}
    local cell = getCell()
    if not cell then return end
    local zombieList = cell:getZombieList()
    if not zombieList then return end
    for i = 0, zombieList:size() - 1 do
        local z = zombieList:get(i)
        if z and not z:isDead() and z:getTarget() == player then
            committedZombies[z] = true
        end
    end
end

-- Apply the sandbox weight multiplier to a corpse item once, at pickup time.
-- This permanently modifies the item's weight for the duration of the session,
-- reducing the stamina drain from encumbrance without removing the speed penalty.
local function applyWeightMultiplier(item)
    local mult = SandboxVars.Camoflesh and SandboxVars.Camoflesh.CorpseWeightMultiplier
    if not mult then mult = 0.5 end
    mult = math.max(0.1, math.min(1.0, mult))
    local w = item:getWeight()
    if w and w > 0 then
        item:setWeight(w * mult)
    end
end

-- ── Event handlers ────────────────────────────────────────────────────────────

-- OnPlayerUpdate fires every tick for every player.
-- We use it to detect transitions between carrying / not carrying a corpse.
local function onPlayerUpdate(player)
    -- Only run for the local player (single-player guard).
    if player ~= getPlayer() then return end

    local corpse   = findCorpse(player)
    local carrying = corpse ~= nil

    if carrying and not wasCarryingCorpse then
        -- Corpse just picked up: snapshot aware zombies, apply weight option.
        recordCommittedZombies(player)
        applyWeightMultiplier(corpse)
        wasCarryingCorpse = true
    elseif not carrying and wasCarryingCorpse then
        -- Corpse just dropped: release all suppression, normal AI resumes.
        committedZombies  = {}
        wasCarryingCorpse = false
    end
end

-- OnZombieUpdate fires every tick for each active zombie.
-- We use it to continuously suppress targeting for non-committed zombies
-- while the player is carrying a corpse.
local function onZombieUpdate(zombie)
    if not wasCarryingCorpse then return end
    if zombie:isDead() then return end

    local player = getPlayer()
    if not player then return end

    -- If this zombie is targeting the local player but was NOT in the
    -- committed snapshot, clear its target to simulate it not noticing the player.
    if zombie:getTarget() == player and not committedZombies[zombie] then
        zombie:setTarget(nil)
    end
end

-- ── Registration ──────────────────────────────────────────────────────────────

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnZombieUpdate.Add(onZombieUpdate)
