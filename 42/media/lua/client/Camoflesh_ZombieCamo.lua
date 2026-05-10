-- ============================================================
-- Camoflesh - Phase 2: Zombie Corpse Camouflage
--
-- When the sandbox option "ZombieIgnoreCorpseCarrier" is enabled,
-- zombies that have NOT yet spotted the player ignore them while
-- they are dragging a zombie corpse.
--
-- How it works:
--   Each tick while the local player is dragging a corpse, we
--   scan nearby grid squares for IsoZombie objects.  Any zombie
--   whose current state is NOT an aggro/attack state (i.e. it
--   hasn't locked onto a target) is made "useless" -- pausing
--   its AI so it cannot detect the player.  When the player
--   drops the corpse every frozen zombie is restored.
--
-- Zombie state names (from FMOD parameters):
--   Unaware : "Idle", "Eating"  (safe to freeze)
--   Alerted : "SearchTarget"    (approaching a noise/smell)
--   Aggro   : "LockTarget", "AttachScratch", "AttackLacerate",
--              "AttackBite", "Attack"  (leave these alone)
--
-- We freeze Idle and Eating zombies, and leave SearchTarget and
-- above alone, so already-chasing zombies keep chasing.
--
-- Set CAMOFLESH_DEBUG = true to print diagnostics to console.
-- ============================================================

local CAMOFLESH_DEBUG = false

local function dbg(msg)
    if CAMOFLESH_DEBUG then
        print("[Camoflesh Camo] " .. tostring(msg))
    end
end

-- ── Constants ────────────────────────────────────────────────────────────────
-- Radius (in tiles) around the player to scan for zombies.
local SCAN_RADIUS = 30

-- Zombie state name substrings that indicate the zombie has already
-- spotted / is hunting the player.  We leave these zombies alone.
local AGGRO_STATES = {
    "LockTarget",
    "AttachScratch",
    "AttackLacerate",
    "AttackBite",
    "Attack",
    "SearchTarget",
}

-- ── Per-player state ─────────────────────────────────────────────────────────
-- Keyed by playerNum.
-- Each entry: { dragging=bool, frozenZombies=table }
-- frozenZombies maps zombie Java object → true (so we can restore them)
local playerState = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Returns true if the zombie is in an aggro/hunt state.
-- (We leave those zombies alone regardless of the option.)
local function isZombieAggro(zombie)
    local stateObj = zombie:getCurrentState()
    if stateObj == nil then return false end
    local stateName = tostring(stateObj)
    for _, aggroKey in ipairs(AGGRO_STATES) do
        if stateName:find(aggroKey, 1, true) then
            return true
        end
    end
    return false
end

-- Scan squares within SCAN_RADIUS around the player and freeze
-- any unaware, non-already-frozen zombie.
local function freezeNearbyUnaware(player, frozenZombies)
    local cell = getCell()
    if not cell then return end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    local frozenCount = 0
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local movers = sq:getMovingObjects()
                for i = 0, movers:size() - 1 do
                    local obj = movers:get(i)
                    if instanceof(obj, "IsoZombie")
                        and not obj:isDead()
                        and not obj:isUseless()
                        and not isZombieAggro(obj)
                    then
                        obj:setUseless(true)
                        frozenZombies[obj] = true
                        frozenCount = frozenCount + 1
                    end
                end
            end
        end
    end
    if frozenCount > 0 then
        dbg("Froze " .. frozenCount .. " zombie(s) this tick")
    end
end

-- Restore all zombies we froze (called when dragging ends).
local function restoreAllFrozen(frozenZombies)
    local count = 0
    for zombie, _ in pairs(frozenZombies) do
        -- Guard: zombie might have died or been removed while frozen
        if zombie and not zombie:isDead() and zombie:getCurrentSquare() ~= nil then
            zombie:setUseless(false)
            count = count + 1
        end
    end
    dbg("Restored " .. count .. " zombie(s)")
    -- Clear the table in place
    for k in pairs(frozenZombies) do
        frozenZombies[k] = nil
    end
end

-- ── Main per-player update ───────────────────────────────────────────────────
local function onPlayerUpdate(player)
    if not SandboxVars or not SandboxVars.Camoflesh then return end

    local num = player:getPlayerNum()
    if not playerState[num] then
        playerState[num] = { dragging = false, frozenZombies = {} }
    end
    local state = playerState[num]

    -- Option disabled: restore anything we froze and bail
    if not SandboxVars.Camoflesh.ZombieIgnoreCorpseCarrier then
        if state.dragging then
            restoreAllFrozen(state.frozenZombies)
            state.dragging = false
        end
        return
    end

    local nowDragging = player:isDraggingCorpse()

    if nowDragging then
        -- Freeze unaware zombies in range each tick.
        -- New zombies may wander into range between ticks, so we
        -- re-scan every update rather than only on drag-start.
        freezeNearbyUnaware(player, state.frozenZombies)
    elseif state.dragging then
        -- Drag just ended: restore all frozen zombies
        dbg("Drag ended. Restoring zombies.")
        restoreAllFrozen(state.frozenZombies)
    end

    state.dragging = nowDragging
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
